defmodule CarscopeWeb.DashboardLive do
  use CarscopeWeb, :live_view

  require Logger
  alias Carscope.{Vehicles, Analytics, MarketAnalytics}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    vehicle = Vehicles.get_vehicle!(id)
    snapshots = Vehicles.list_price_snapshots(vehicle.id)
    stats = Vehicles.price_stats(vehicle.id)

    # Try analytics service (non-blocking)
    prices = Enum.map(snapshots, & &1.price_cents)
    analysis = fetch_analysis(prices)
    depreciation = fetch_depreciation(snapshots)
    market_position = fetch_market_position(vehicle.id)
    deal_scores = fetch_deal_scores(snapshots, vehicle.id)
    data_quality = fetch_data_quality(prices)
    outliers = fetch_outliers(prices)
    dom_stats = Vehicles.days_on_market_stats(vehicle.id)

    {:ok,
     socket
     |> assign(:vehicle, vehicle)
     |> assign(:snapshots, snapshots)
     |> assign(:stats, stats)
     |> assign(:analysis, analysis)
     |> assign(:depreciation, depreciation)
     |> assign(:market_position, market_position)
     |> assign(:deal_scores, deal_scores)
     |> assign(:data_quality, data_quality)
     |> assign(:outliers, outliers)
     |> assign(:dom_stats, dom_stats)
     |> assign(:searching, false)}
  end

  @impl true
  def handle_event("refresh-prices", _params, socket) do
    vehicle = socket.assigns.vehicle
    query = "#{vehicle.year} #{vehicle.make} #{vehicle.model} price for sale"

    socket = assign(socket, searching: true)
    send(self(), {:do_search, query})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:do_search, query}, socket) do
    vehicle = socket.assigns.vehicle

    case Carscope.BraveSearch.search_cars(query) do
      {:ok, results} ->
        Enum.each(results, fn result ->
          Vehicles.create_price_snapshot(%{
            time: DateTime.utc_now(),
            vehicle_id: vehicle.id,
            price_cents: result.price_cents,
            mileage: result.mileage,
            source: result.source,
            url: result.url
          })
        end)

        snapshots = Vehicles.list_price_snapshots(vehicle.id)
        stats = Vehicles.price_stats(vehicle.id)
        prices = Enum.map(snapshots, & &1.price_cents)
        analysis = fetch_analysis(prices)
        depreciation = fetch_depreciation(snapshots)
        deal_scores = fetch_deal_scores(snapshots, vehicle.id)
        data_quality = fetch_data_quality(prices)
        outliers = fetch_outliers(prices)
        dom_stats = Vehicles.days_on_market_stats(vehicle.id)

        {:noreply,
         socket
         |> assign(snapshots: snapshots, stats: stats, analysis: analysis,
                   depreciation: depreciation, deal_scores: deal_scores,
                   data_quality: data_quality, outliers: outliers,
                   dom_stats: dom_stats, searching: false)
         |> put_flash(:info, "Added #{length(results)} price points")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(searching: false)
         |> put_flash(:error, "Search failed: #{inspect(reason)}")}
    end
  end

  defp fetch_analysis(prices) do
    case Analytics.analyze_prices(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Analytics unavailable: #{Exception.message(e)}")
      nil
  end

  defp fetch_market_position(vehicle_id) do
    MarketAnalytics.vehicle_market_position(vehicle_id)
  rescue
    e in [Postgrex.Error, DBConnection.ConnectionError] ->
      Logger.debug("Market query failed: #{Exception.message(e)}")
      nil
  end

  defp fetch_deal_scores(snapshots, _vehicle_id) when length(snapshots) < 3, do: %{}

  defp fetch_deal_scores(snapshots, vehicle_id) do
    market_prices = Vehicles.get_market_prices(vehicle_id)

    snapshots
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {snap, idx}, acc ->
      case Analytics.deal_score(snap.price_cents, market_prices) do
        {:ok, result} -> Map.put(acc, idx, result)
        _ -> acc
      end
    end)
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Deal scoring unavailable: #{Exception.message(e)}")
      %{}
  end

  defp fetch_depreciation(snapshots) when length(snapshots) < 2, do: nil

  defp fetch_depreciation(snapshots) do
    case Analytics.depreciation(snapshots) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Depreciation service unavailable: #{Exception.message(e)}")
      nil
  end


  defp fetch_data_quality(prices) when length(prices) < 3, do: nil

  defp fetch_data_quality(prices) do
    case Analytics.data_quality(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Data quality unavailable: #{Exception.message(e)}")
      nil
  end

  defp fetch_outliers(prices) when length(prices) < 3, do: nil

  defp fetch_outliers(prices) do
    case Analytics.outliers(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Outlier detection unavailable: #{Exception.message(e)}")
      nil
  end

  defp freshness_class(days) when is_integer(days) do
    cond do
      days >= 60 -> {"Stale", "bg-error/10 text-error"}
      days >= 30 -> {"Negotiable", "bg-warning/10 text-warning"}
      days >= 14 -> {"Sitting", "bg-info/10 text-info"}
      true -> {"Fresh", "bg-success/10 text-success"}
    end
  end

  defp freshness_class(_), do: {"—", ""}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="text-primary hover:underline text-sm">← Back to search</.link>

      <div class="mt-4 mb-8">
        <h1 class="text-3xl font-bold">
          {@vehicle.year} {@vehicle.make} {@vehicle.model}
        </h1>
        <p :if={@vehicle.trim} class="text-base-content/60">{@vehicle.trim}</p>
      </div>

      <%!-- Stats Cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Avg Price</div>
          <div class="text-2xl font-bold">{format_price(@stats.avg_price)}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Min Price</div>
          <div class="text-2xl font-bold text-success">{format_price(@stats.min_price)}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Max Price</div>
          <div class="text-2xl font-bold text-error">{format_price(@stats.max_price)}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Data Points</div>
          <div class="text-2xl font-bold">{@stats.count}</div>
        </div>
      </div>

      <%!-- Market Comparison (from pg_duckdb) --%>
      <div :if={@market_position} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Market Comparison</h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <div class="text-sm text-base-content/60">Your Avg</div>
            <div class="text-xl font-bold">{format_price(@market_position["vehicle_avg_price"])}</div>
          </div>
          <div>
            <div class="text-sm text-base-content/60">Market Avg</div>
            <div class="text-xl font-bold">{format_price(@market_position["market_avg"])}</div>
          </div>
          <div>
            <div class="text-sm text-base-content/60">Z-Score</div>
            <div class="text-xl font-bold">
              {if z = @market_position["z_score"], do: "#{z}", else: "—"}
            </div>
            <div class="text-xs text-base-content/60">
              <%= cond do %>
                <% (@market_position["z_score"] || 0) < -1 -> %>
                  Well below market
                <% (@market_position["z_score"] || 0) > 1 -> %>
                  Well above market
                <% true -> %>
                  Near market average
              <% end %>
            </div>
          </div>
          <div>
            <div class="text-sm text-base-content/60">Market Size</div>
            <div class="text-xl font-bold">{@market_position["market_count"]} listings</div>
          </div>
        </div>
        <div class="mt-3 text-right">
          <.link navigate={~p"/market"} class="text-primary hover:underline text-sm">
            View full market analytics &rarr;
          </.link>
        </div>
      </div>

      <%!-- Analytics (from OCaml service) --%>
      <div :if={@analysis} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Analytics (OxCaml)</h2>
        <div class="grid grid-cols-2 md:grid-cols-6 gap-4 text-sm">
          <div>
            <span class="text-base-content/60">Median</span>
            <div class="font-mono">{format_price(@analysis["median"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">Std Dev</span>
            <div class="font-mono">{format_price(@analysis["std_dev"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">IQR</span>
            <div class="font-mono">{format_price(@analysis["iqr"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">P10</span>
            <div class="font-mono">{format_price(@analysis["p10"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">P25</span>
            <div class="font-mono">{format_price(@analysis["p25"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">P90</span>
            <div class="font-mono">{format_price(@analysis["p90"])}</div>
          </div>
        </div>
      </div>

      <%!-- Depreciation (from OCaml service) --%>
      <div :if={@depreciation} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">
          Depreciation Curve
          <span :if={@depreciation["model"]} class="text-xs font-normal text-base-content/40 ml-2">
            ({@depreciation["model"]} model, R²={@depreciation["r_squared"]})
          </span>
        </h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm mb-4">
          <div>
            <span class="text-base-content/60">Annual Depreciation</span>
            <div class="text-xl font-bold text-warning">{@depreciation["annual_depreciation_pct"]}%</div>
          </div>
          <div>
            <span class="text-base-content/60">Estimated Initial Price</span>
            <div class="font-mono">{format_price(@depreciation["initial_price"])}</div>
          </div>
          <div>
            <span class="text-base-content/60">Data Points Used</span>
            <div class="font-mono">{@depreciation["data_points"]}</div>
          </div>
          <div :if={@depreciation["alt_r_squared"]}>
            <span class="text-base-content/60">Alt Model R²</span>
            <div class="font-mono text-base-content/40">{@depreciation["alt_r_squared"]}</div>
          </div>
        </div>
        <div :if={@depreciation["predictions"]} class="border-t pt-4">
          <h3 class="text-sm font-medium text-base-content/60 mb-2">Predicted Future Prices</h3>
          <div class="flex gap-4">
            <%= for pred <- @depreciation["predictions"] do %>
              <div class="bg-base-200 rounded px-3 py-2 text-center">
                <div class="text-xs text-base-content/60">+{pred["years_from_now"]}yr</div>
                <div class="font-mono font-bold">{format_price(pred["predicted_price"])}</div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Data Quality + Outliers row --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div :if={@data_quality} class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-3">
            Data Quality
            <span class={[
              "ml-2 text-2xl font-bold",
              if(@data_quality["grade"] in ~w(A B), do: "text-success",
                else: if(@data_quality["grade"] == "C", do: "text-warning", else: "text-error"))
            ]}>
              {@data_quality["grade"]}
            </span>
            <span class="text-xs text-base-content/40 font-normal ml-1">
              ({@data_quality["composite_score"]}/100)
            </span>
          </h2>
          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <span class="text-base-content/60">Sample Size</span>
              <div class="font-mono">{@data_quality["sample_size"]} pts ({@data_quality["dimensions"]["sample_size_score"] |> trunc()}%)</div>
            </div>
            <div>
              <span class="text-base-content/60">Spread (CV)</span>
              <div class="font-mono">{@data_quality["details"]["cv"]} ({@data_quality["dimensions"]["spread_score"] |> trunc()}%)</div>
            </div>
            <div>
              <span class="text-base-content/60">Skewness</span>
              <div class="font-mono">{@data_quality["details"]["skewness"]}</div>
            </div>
            <div>
              <span class="text-base-content/60">Kurtosis</span>
              <div class="font-mono">{@data_quality["details"]["kurtosis"]}</div>
            </div>
          </div>
        </div>

        <div :if={@outliers} class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-3">
            Outlier Detection
            <span class="text-xs text-base-content/40 font-normal ml-1">
              ({@outliers["outlier_count"]} of {@outliers["total_count"]} flagged)
            </span>
          </h2>
          <%= if @outliers["outlier_count"] > 0 do %>
            <div class="space-y-2">
              <%= for flag <- @outliers["flagged"] do %>
                <div class="flex items-center gap-3 text-sm">
                  <span class={[
                    "px-2 py-0.5 rounded-full text-xs font-medium",
                    if(flag["severity"] == "extreme", do: "bg-error/20 text-error",
                      else: if(flag["severity"] == "high", do: "bg-warning/20 text-warning",
                        else: "bg-info/10 text-info"))
                  ]}>
                    {flag["severity"]}
                  </span>
                  <span class="font-mono">{format_price(flag["price"])}</span>
                  <span class="text-base-content/40">z={flag["z_score"]} ({flag["method"]})</span>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-success">No outliers detected — data looks clean.</p>
          <% end %>
          <div class="mt-3 text-xs text-base-content/40">
            IQR bounds: {format_price(@outliers["thresholds"]["iqr_lower"])} – {format_price(@outliers["thresholds"]["iqr_upper"])}
          </div>
        </div>
      </div>

      <%!-- Days on Market --%>
      <div :if={@dom_stats != []} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Listing Freshness</h2>
        <div class="space-y-2">
          <%= for listing <- Enum.take(@dom_stats, 15) do %>
            <% {label, badge_class} = freshness_class(listing["days_on_market"]) %>
            <div class="flex items-center gap-3 text-sm">
              <span class={"inline-block w-20 text-center px-2 py-0.5 rounded-full text-xs font-medium #{badge_class}"}>
                {label}
              </span>
              <span class="font-mono w-16 text-right">{listing["days_on_market"]}d</span>
              <span class="font-mono font-bold">{format_price(listing["min_price"])}</span>
              <%= if listing["times_seen"] > 1 do %>
                <span class="text-base-content/40">seen {listing["times_seen"]}x</span>
              <% end %>
              <a :if={listing["url"]} href={listing["url"]} target="_blank" class="text-primary hover:underline ml-auto truncate max-w-xs">
                {URI.parse(listing["url"]).host |> String.replace(~r/^www\./, "")}
              </a>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Price History --%>
      <div class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-lg font-semibold">Price History</h2>
          <button
            phx-click="refresh-prices"
            disabled={@searching}
            class="bg-primary text-primary-content px-4 py-1.5 rounded text-sm hover:bg-primary/80 disabled:opacity-50"
          >
            <%= if @searching, do: "Fetching...", else: "Fetch New Prices" %>
          </button>
        </div>

          <%!-- Price chart (Chart.js) --%>
        <div
          :if={@snapshots != []}
          id="price-chart"
          phx-hook="PriceChart"
          phx-update="ignore"
          data-snapshots={Jason.encode!(Enum.map(@snapshots, fn s -> %{time: s.time, price: div(s.price_cents, 100)} end))}
          class="mb-6 h-64"
        >
          <canvas></canvas>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b text-left text-base-content/60">
                <th class="py-2 pr-4">Date</th>
                <th class="py-2 pr-4">Price</th>
                <th class="py-2 pr-4">Mileage</th>
                <th class="py-2 pr-4">Source</th>
                <th class="py-2 pr-4">Deal</th>
                <th class="py-2">Link</th>
              </tr>
            </thead>
            <tbody>
              <%= for {snap, idx} <- Enum.take(@snapshots, 25) |> Enum.with_index() do %>
                <tr class="border-b hover:bg-base-200">
                  <td class="py-2 pr-4 text-base-content/60">{format_date(snap.time)}</td>
                  <td class="py-2 pr-4 font-mono font-bold">{format_price(snap.price_cents)}</td>
                  <td class="py-2 pr-4">
                    <%= if snap.mileage do %>
                      {snap.mileage |> Integer.to_string() |> format_number()} mi
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="py-2 pr-4">{snap.source || "—"}</td>
                  <td class="py-2 pr-4">
                    <% deal = @deal_scores[idx] %>
                    <span
                      :if={deal}
                      class={[
                        "inline-block px-2 py-0.5 rounded-full text-xs font-medium",
                        deal_badge_class(deal["label"])
                      ]}
                    >
                      {deal["label"]} ({deal["score"]})
                    </span>
                  </td>
                  <td class="py-2">
                    <a :if={snap.url} href={snap.url} target="_blank" class="text-primary hover:underline">
                      View →
                    </a>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
