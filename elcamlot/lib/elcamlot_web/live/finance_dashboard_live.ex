defmodule ElcamlotWeb.FinanceDashboardLive do
  use ElcamlotWeb, :live_view

  require Logger
  alias Elcamlot.{Markets, Analytics}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    instrument = Markets.get_instrument!(id)
    bars = Markets.list_bars(instrument.id, limit: 365)
    stats = Markets.price_stats(instrument.id)

    close_prices = bars |> Enum.reverse() |> Enum.map(& &1.close_cents)
    volatility = fetch_volatility(close_prices)
    data_quality = fetch_data_quality(close_prices)
    outliers = fetch_outliers(close_prices)

    {:ok,
     socket
     |> assign(:instrument, instrument)
     |> assign(:bars, bars)
     |> assign(:stats, stats)
     |> assign(:volatility, volatility)
     |> assign(:data_quality, data_quality)
     |> assign(:outliers, outliers)}
  end

  defp fetch_volatility(prices) when length(prices) < 2, do: nil
  defp fetch_volatility(prices) do
    case Analytics.volatility(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp fetch_data_quality(prices) when length(prices) < 3, do: nil
  defp fetch_data_quality(prices) do
    case Analytics.data_quality(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp fetch_outliers(prices) when length(prices) < 3, do: nil
  defp fetch_outliers(prices) do
    case Analytics.outliers(prices) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp format_cents(nil), do: "—"
  defp format_cents(cents) when is_number(cents) do
    dollars = cents / 100
    if dollars >= 1000 do
      "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
    else
      "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
    end
  end

  defp format_vol(nil), do: "—"
  defp format_vol(v) when is_number(v), do: "#{Float.round(v * 100, 1)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <.link navigate={~p"/finance"} class="text-primary hover:underline text-sm">&larr; Back to instruments</.link>

      <div class="mt-4 mb-8">
        <h1 class="text-3xl font-bold">
          {@instrument.symbol}
          <span :if={@instrument.name} class="text-lg font-normal text-base-content/60 ml-2">{@instrument.name}</span>
        </h1>
        <div class="flex gap-2 mt-1">
          <span class="px-2 py-0.5 rounded-full text-xs bg-primary/10 text-primary">{@instrument.asset_class}</span>
          <span :if={@instrument.exchange} class="px-2 py-0.5 rounded-full text-xs bg-base-200 text-base-content/60">{@instrument.exchange}</span>
        </div>
      </div>

      <%!-- Stats Cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Avg Close</div>
          <div class="text-2xl font-bold">{format_cents(@stats["avg_price"])}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Median</div>
          <div class="text-2xl font-bold">{format_cents(@stats["median"])}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">Low</div>
          <div class="text-2xl font-bold text-success">{format_cents(@stats["min_price"])}</div>
        </div>
        <div class="bg-base-100 rounded-lg shadow p-4">
          <div class="text-sm text-base-content/60">High</div>
          <div class="text-2xl font-bold text-error">{format_cents(@stats["max_price"])}</div>
        </div>
      </div>

      <%!-- Price Chart --%>
      <div :if={@bars != []} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Price History</h2>
        <div
          id="price-chart"
          phx-hook="PriceChart"
          phx-update="ignore"
          data-snapshots={Jason.encode!(Enum.map(Enum.reverse(@bars), fn b -> %{time: b.time, price: div(b.close_cents, 100)} end))}
          class="h-64"
        >
          <canvas></canvas>
        </div>
        <div class="mt-2 text-xs text-base-content/40">
          {length(@bars)} bars &middot;
          {@stats["first_bar"]} to {@stats["last_bar"]}
        </div>
      </div>

      <%!-- Volatility + Data Quality row --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div :if={@volatility} class="bg-base-100 rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-3">Volatility</h2>
          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <span class="text-base-content/60">Daily Vol</span>
              <div class="text-xl font-bold">{format_vol(@volatility["daily_vol"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">Annualized Vol</span>
              <div class="text-xl font-bold text-warning">{format_vol(@volatility["annualized_vol"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">Mean Return</span>
              <div class="font-mono">{format_vol(@volatility["mean_return"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">Data Points</span>
              <div class="font-mono">{@volatility["num_returns"]}</div>
            </div>
          </div>
        </div>

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
              <div class="font-mono">{@data_quality["sample_size"]} pts</div>
            </div>
            <div>
              <span class="text-base-content/60">CV</span>
              <div class="font-mono">{@data_quality["details"]["cv"]}</div>
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
      </div>

      <%!-- Outliers --%>
      <div :if={@outliers && @outliers["outlier_count"] > 0} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-3">
          Outlier Detection
          <span class="text-xs text-base-content/40 font-normal ml-1">
            ({@outliers["outlier_count"]} of {@outliers["total_count"]} flagged)
          </span>
        </h2>
        <div class="space-y-2">
          <%= for flag <- Enum.take(@outliers["flagged"], 10) do %>
            <div class="flex items-center gap-3 text-sm">
              <span class={[
                "px-2 py-0.5 rounded-full text-xs font-medium",
                if(flag["severity"] == "extreme", do: "bg-error/20 text-error",
                  else: if(flag["severity"] == "high", do: "bg-warning/20 text-warning",
                    else: "bg-info/10 text-info"))
              ]}>
                {flag["severity"]}
              </span>
              <span class="font-mono">{format_cents(flag["price"])}</span>
              <span class="text-base-content/40">z={flag["z_score"]}</span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Recent Bars Table --%>
      <div class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Recent Bars</h2>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b text-left text-base-content/60">
                <th class="py-2 pr-4">Date</th>
                <th class="py-2 pr-4">Open</th>
                <th class="py-2 pr-4">High</th>
                <th class="py-2 pr-4">Low</th>
                <th class="py-2 pr-4">Close</th>
                <th class="py-2">Volume</th>
              </tr>
            </thead>
            <tbody>
              <%= for bar <- Enum.take(@bars, 30) do %>
                <tr class="border-b hover:bg-base-200/30">
                  <td class="py-2 pr-4 text-base-content/60">{Calendar.strftime(bar.time, "%b %d, %Y")}</td>
                  <td class="py-2 pr-4 font-mono">{format_cents(bar.open_cents)}</td>
                  <td class="py-2 pr-4 font-mono text-success">{format_cents(bar.high_cents)}</td>
                  <td class="py-2 pr-4 font-mono text-error">{format_cents(bar.low_cents)}</td>
                  <td class="py-2 pr-4 font-mono font-bold">{format_cents(bar.close_cents)}</td>
                  <td class="py-2 font-mono text-base-content/60">{format_volume(bar.volume)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp format_volume(nil), do: "—"
  defp format_volume(v) when v >= 1_000_000, do: "#{Float.round(v / 1_000_000, 1)}M"
  defp format_volume(v) when v >= 1_000, do: "#{Float.round(v / 1_000, 1)}K"
  defp format_volume(v), do: "#{v}"
end
