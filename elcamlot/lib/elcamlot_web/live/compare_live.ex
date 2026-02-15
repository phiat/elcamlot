defmodule ElcamlotWeb.CompareLive do
  use ElcamlotWeb, :live_view

  require Logger
  alias Elcamlot.{Vehicles, Analytics}

  @max_vehicles 4
  @palette ~w(#3b82f6 #f97316 #10b981 #ef4444)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_term, "")
     |> assign(:search_results, [])
     |> assign(:slots, [])
     |> assign(:palette, @palette)
     |> assign(:max_vehicles, @max_vehicles)}
  end

  @impl true
  def handle_event("search", %{"term" => term}, socket) do
    results =
      if String.length(term) >= 2,
        do: Vehicles.search_vehicles(term),
        else: []

    {:noreply, assign(socket, search_term: term, search_results: results)}
  end

  def handle_event("add-vehicle", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    slots = socket.assigns.slots

    already_added = Enum.any?(slots, fn s -> s.vehicle.id == id end)

    if already_added or length(slots) >= @max_vehicles do
      {:noreply, socket}
    else
      vehicle = Vehicles.get_vehicle!(id)
      snapshots = Vehicles.list_price_snapshots(vehicle.id)
      stats = Vehicles.price_stats(vehicle.id)
      prices = Enum.map(snapshots, & &1.price_cents)
      market_prices = Vehicles.get_market_prices(vehicle.id)
      depreciation = fetch_depreciation(snapshots)
      deal_score = fetch_latest_deal_score(prices, market_prices)

      slot = %{
        vehicle: vehicle,
        snapshots: snapshots,
        stats: stats,
        depreciation: depreciation,
        deal_score: deal_score,
        color: Enum.at(@palette, length(slots))
      }

      slots = slots ++ [slot]

      {:noreply,
       socket
       |> assign(:slots, slots)
       |> assign(:search_term, "")
       |> assign(:search_results, [])}
    end
  end

  def handle_event("remove-vehicle", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    slots = Enum.reject(socket.assigns.slots, fn s -> s.vehicle.id == id end)

    # Re-assign palette colors based on new positions
    slots =
      slots
      |> Enum.with_index()
      |> Enum.map(fn {slot, idx} -> %{slot | color: Enum.at(@palette, idx)} end)

    {:noreply, assign(socket, :slots, slots)}
  end

  # --- Private helpers ---

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

  defp fetch_latest_deal_score(prices, _market_prices) when length(prices) < 3, do: nil
  defp fetch_latest_deal_score([], _), do: nil

  defp fetch_latest_deal_score(prices, market_prices) do
    latest_price = List.first(prices)

    case Analytics.deal_score(latest_price, market_prices) do
      {:ok, result} -> result
      _ -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Deal scoring unavailable: #{Exception.message(e)}")
      nil
  end

  defp chart_datasets(slots) do
    Enum.map(slots, fn slot ->
      points =
        slot.snapshots
        |> Enum.sort_by(& &1.time, DateTime)
        |> Enum.map(fn s ->
          %{time: DateTime.to_iso8601(s.time), price: div(s.price_cents, 100)}
        end)

      %{
        label: "#{slot.vehicle.year} #{slot.vehicle.make} #{slot.vehicle.model}",
        color: slot.color,
        data: points
      }
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :chart_datasets, chart_datasets(assigns.slots))

    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="text-primary hover:underline text-sm">&larr; Back to search</.link>

      <h1 class="text-3xl font-bold mt-4 mb-6">Compare Vehicles</h1>

      <%!-- Vehicle Search / Add --%>
      <div :if={length(@slots) < @max_vehicles} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-3">
          Add Vehicle ({length(@slots)}/{@max_vehicles})
        </h2>
        <form phx-change="search" phx-submit="search" class="mb-3">
          <input
            type="text"
            name="term"
            value={@search_term}
            placeholder="Search by make or model..."
            phx-debounce="300"
            autocomplete="off"
            class="input input-bordered w-full max-w-md"
          />
        </form>
        <div :if={@search_results != []} class="border rounded-lg max-h-48 overflow-y-auto">
          <%= for v <- @search_results do %>
            <button
              phx-click="add-vehicle"
              phx-value-id={v.id}
              class="w-full text-left px-4 py-2 hover:bg-base-200 border-b last:border-b-0 flex justify-between items-center"
            >
              <span class="font-medium">{v.year} {v.make} {v.model}<span :if={v.trim} class="text-base-content/60 ml-1">{v.trim}</span></span>
              <span :if={v.avg_price} class="text-sm text-base-content/60 font-mono">{format_price(v.avg_price)}</span>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- No vehicles selected --%>
      <div :if={@slots == []} class="text-center text-base-content/40 py-16">
        <p class="text-lg">Search and add 2-4 vehicles to compare them side by side.</p>
      </div>

      <%!-- Comparison Chart --%>
      <div :if={length(@slots) >= 2} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Price History Overlay</h2>
        <div
          id="compare-chart"
          phx-hook="CompareChart"
          data-datasets={Jason.encode!(@chart_datasets)}
          class="h-80"
        >
          <canvas></canvas>
        </div>
      </div>

      <%!-- Side-by-side columns --%>
      <div :if={@slots != []} class={"grid gap-6 #{column_class(length(@slots))}"}>
        <%= for slot <- @slots do %>
          <div class="bg-base-100 rounded-lg shadow p-6">
            <%!-- Header with remove button --%>
            <div class="flex justify-between items-start mb-4">
              <div>
                <div class="flex items-center gap-2">
                  <span class="inline-block w-3 h-3 rounded-full" style={"background: #{slot.color}"}></span>
                  <h3 class="text-lg font-bold">{slot.vehicle.year} {slot.vehicle.make} {slot.vehicle.model}</h3>
                </div>
                <p :if={slot.vehicle.trim} class="text-sm text-base-content/60 ml-5">{slot.vehicle.trim}</p>
              </div>
              <button
                phx-click="remove-vehicle"
                phx-value-id={slot.vehicle.id}
                class="text-base-content/40 hover:text-error text-lg leading-none"
                title="Remove"
              >
                &times;
              </button>
            </div>

            <%!-- Price Stats --%>
            <div class="space-y-2 text-sm mb-4">
              <div class="flex justify-between">
                <span class="text-base-content/60">Avg Price</span>
                <span class="font-mono font-bold">{format_price(slot.stats["avg_price"])}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Median</span>
                <span class="font-mono font-bold">{format_price(slot.stats["median"])}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Min</span>
                <span class="font-mono text-success">{format_price(slot.stats["min_price"])}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Max</span>
                <span class="font-mono text-error">{format_price(slot.stats["max_price"])}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/60">Data Points</span>
                <span class="font-mono">{slot.stats["count"]}</span>
              </div>
            </div>

            <%!-- Deal Score --%>
            <div :if={slot.deal_score} class="border-t pt-3 mb-4">
              <h4 class="text-sm font-medium text-base-content/60 mb-2">Latest Deal Score</h4>
              <div class="flex items-center gap-2">
                <span class={[
                  "inline-block px-3 py-1 rounded-full text-sm font-medium",
                  deal_badge_class(slot.deal_score["label"])
                ]}>
                  {slot.deal_score["label"]}
                </span>
                <span class="font-mono text-base-content/60">{slot.deal_score["score"]}/100</span>
              </div>
            </div>

            <%!-- Depreciation --%>
            <div :if={slot.depreciation} class="border-t pt-3">
              <h4 class="text-sm font-medium text-base-content/60 mb-2">Depreciation</h4>
              <div class="space-y-1 text-sm">
                <div class="flex justify-between">
                  <span class="text-base-content/60">Annual Rate</span>
                  <span class="font-mono text-warning">{slot.depreciation["annual_depreciation_pct"]}%</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-base-content/60">Model</span>
                  <span class="font-mono">{slot.depreciation["model"] || "—"}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-base-content/60">R&sup2;</span>
                  <span class="font-mono">{slot.depreciation["r_squared"] || "—"}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-base-content/60">Est. Initial</span>
                  <span class="font-mono">{format_price(slot.depreciation["initial_price"])}</span>
                </div>
              </div>

              <%!-- Predictions --%>
              <div :if={slot.depreciation["predictions"]} class="mt-3">
                <h5 class="text-xs text-base-content/40 mb-1">Predicted</h5>
                <div class="flex gap-2 flex-wrap">
                  <%= for pred <- slot.depreciation["predictions"] do %>
                    <div class="bg-base-200 rounded px-2 py-1 text-center text-xs">
                      <div class="text-base-content/60">+{pred["years_from_now"]}yr</div>
                      <div class="font-mono font-bold">{format_price(pred["predicted_price"])}</div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Link to full dashboard --%>
            <div class="border-t pt-3 mt-3">
              <.link navigate={~p"/vehicle/#{slot.vehicle.id}"} class="text-primary hover:underline text-sm">
                Full dashboard &rarr;
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp column_class(1), do: "grid-cols-1 max-w-md"
  defp column_class(2), do: "grid-cols-1 md:grid-cols-2"
  defp column_class(3), do: "grid-cols-1 md:grid-cols-3"
  defp column_class(_), do: "grid-cols-1 md:grid-cols-2 lg:grid-cols-4"
end
