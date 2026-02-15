defmodule ElcamlotWeb.CrossAnalyticsLive do
  use ElcamlotWeb, :live_view

  require Logger
  alias Elcamlot.{Vehicles, Markets, Analytics}

  @impl true
  def mount(_params, _session, socket) do
    vehicles = Vehicles.list_vehicles()
    instruments = Markets.list_instruments()

    {:ok,
     socket
     |> assign(:vehicles, vehicles)
     |> assign(:instruments, instruments)
     |> assign(:selected_vehicle_id, nil)
     |> assign(:selected_instrument_id, nil)
     |> assign(:vehicle, nil)
     |> assign(:instrument, nil)
     |> assign(:vehicle_prices, [])
     |> assign(:instrument_prices, [])
     |> assign(:correlation, nil)
     |> assign(:chart_data, nil)
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("select-vehicle", %{"vehicle_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_vehicle_id, nil)
     |> assign(:vehicle, nil)
     |> assign(:vehicle_prices, [])
     |> assign(:correlation, nil)
     |> assign(:chart_data, nil)}
  end

  def handle_event("select-vehicle", %{"vehicle_id" => id}, socket) do
    vehicle_id = String.to_integer(id)
    vehicle = Vehicles.get_vehicle!(vehicle_id)
    snapshots = Vehicles.list_price_snapshots(vehicle_id)

    socket =
      socket
      |> assign(:selected_vehicle_id, vehicle_id)
      |> assign(:vehicle, vehicle)
      |> assign(:vehicle_prices, snapshots)

    socket = maybe_run_correlation(socket)
    {:noreply, socket}
  end

  def handle_event("select-instrument", %{"instrument_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_instrument_id, nil)
     |> assign(:instrument, nil)
     |> assign(:instrument_prices, [])
     |> assign(:correlation, nil)
     |> assign(:chart_data, nil)}
  end

  def handle_event("select-instrument", %{"instrument_id" => id}, socket) do
    instrument_id = String.to_integer(id)
    instrument = Markets.get_instrument!(instrument_id)
    bars = Markets.list_bars(instrument_id, limit: 365)

    socket =
      socket
      |> assign(:selected_instrument_id, instrument_id)
      |> assign(:instrument, instrument)
      |> assign(:instrument_prices, bars)

    socket = maybe_run_correlation(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:run_correlation, socket) do
    vehicle_series = socket.assigns.vehicle_prices
                     |> Enum.reverse()
                     |> Enum.map(& &1.price_cents)

    instrument_series = socket.assigns.instrument_prices
                        |> Enum.reverse()
                        |> Enum.map(& &1.close_cents)

    # Align series to the shorter length
    min_len = min(length(vehicle_series), length(instrument_series))
    vehicle_trimmed = Enum.take(vehicle_series, -min_len)
    instrument_trimmed = Enum.take(instrument_series, -min_len)

    correlation = fetch_correlation(vehicle_trimmed, instrument_trimmed)
    chart_data = build_chart_data(socket.assigns.vehicle_prices, socket.assigns.instrument_prices)

    {:noreply,
     socket
     |> assign(:correlation, correlation)
     |> assign(:chart_data, chart_data)
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  defp maybe_run_correlation(socket) do
    vehicle_prices = socket.assigns.vehicle_prices
    instrument_prices = socket.assigns.instrument_prices

    if length(vehicle_prices) >= 2 and length(instrument_prices) >= 2 do
      send(self(), :run_correlation)
      assign(socket, :loading, true)
    else
      socket
      |> assign(:correlation, nil)
      |> assign(:chart_data, nil)
      |> assign(:loading, false)
    end
  end

  defp fetch_correlation(series_a, _series_b) when length(series_a) < 2, do: nil
  defp fetch_correlation(_series_a, series_b) when length(series_b) < 2, do: nil

  defp fetch_correlation(series_a, series_b) do
    case Analytics.correlation(series_a, series_b) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  rescue
    e in [Req.TransportError, Req.HTTPError] ->
      Logger.debug("Correlation service unavailable: #{Exception.message(e)}")
      nil
  end

  defp build_chart_data(vehicle_snapshots, instrument_bars) do
    vehicle_points =
      vehicle_snapshots
      |> Enum.reverse()
      |> Enum.map(fn s -> %{time: DateTime.to_iso8601(s.time), price: div(s.price_cents, 100)} end)

    instrument_points =
      instrument_bars
      |> Enum.reverse()
      |> Enum.map(fn b -> %{time: DateTime.to_iso8601(b.time), price: div(b.close_cents, 100)} end)

    %{vehicle: vehicle_points, instrument: instrument_points}
  end

  defp correlation_strength(nil), do: {"—", "text-base-content/40"}

  defp correlation_strength(r) when is_number(r) do
    abs_r = abs(r)

    cond do
      abs_r >= 0.8 -> {"Very Strong", "text-error font-bold"}
      abs_r >= 0.6 -> {"Strong", "text-warning font-bold"}
      abs_r >= 0.4 -> {"Moderate", "text-info"}
      abs_r >= 0.2 -> {"Weak", "text-base-content/60"}
      true -> {"Very Weak", "text-base-content/40"}
    end
  end

  defp correlation_direction(nil), do: "—"
  defp correlation_direction(r) when r > 0.05, do: "Positive (move together)"
  defp correlation_direction(r) when r < -0.05, do: "Negative (move opposite)"
  defp correlation_direction(_), do: "No clear direction"

  defp format_r(nil), do: "—"
  defp format_r(r) when is_number(r), do: :erlang.float_to_binary(r * 1.0, decimals: 4)

  defp format_r_squared(nil), do: "—"
  defp format_r_squared(r) when is_number(r), do: :erlang.float_to_binary(r * r * 1.0, decimals: 4)

  defp vehicle_label(nil), do: "Vehicle"

  defp vehicle_label(v) do
    "#{v.year} #{v.make} #{v.model}"
  end

  defp instrument_label(nil), do: "Instrument"
  defp instrument_label(i), do: i.symbol

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="text-primary hover:underline text-sm">&larr; Back to search</.link>

      <div class="mt-4 mb-8">
        <h1 class="text-3xl font-bold">Cross Analytics</h1>
        <p class="text-base-content/60 mt-1">Compare vehicle price history against financial instruments</p>
      </div>

      <%!-- Selection Controls --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div class="bg-base-100 rounded-lg shadow p-6">
          <label class="text-sm font-medium text-base-content/60 block mb-2">Vehicle</label>
          <select
            phx-change="select-vehicle"
            name="vehicle_id"
            class="select select-bordered w-full"
          >
            <option value="">Select a vehicle...</option>
            <%= for v <- @vehicles do %>
              <option value={v.id} selected={v.id == @selected_vehicle_id}>
                {v.year} {v.make} {v.model} {v.trim || ""}
              </option>
            <% end %>
          </select>
          <div :if={@vehicle} class="mt-2 text-xs text-base-content/40">
            {length(@vehicle_prices)} price snapshots
          </div>
        </div>

        <div class="bg-base-100 rounded-lg shadow p-6">
          <label class="text-sm font-medium text-base-content/60 block mb-2">Financial Instrument</label>
          <select
            phx-change="select-instrument"
            name="instrument_id"
            class="select select-bordered w-full"
          >
            <option value="">Select an instrument...</option>
            <%= for i <- @instruments do %>
              <option value={i.id} selected={i.id == @selected_instrument_id}>
                {i.symbol} {if i.name, do: "— #{i.name}", else: ""}
              </option>
            <% end %>
          </select>
          <div :if={@instrument} class="mt-2 text-xs text-base-content/40">
            {length(@instrument_prices)} price bars
          </div>
        </div>
      </div>

      <%!-- Loading indicator --%>
      <div :if={@loading} class="text-center py-8">
        <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
        <p class="mt-2 text-base-content/60">Computing correlation...</p>
      </div>

      <%!-- Correlation Results --%>
      <div :if={@correlation && !@loading} class="mb-8">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Pearson r</div>
            <div class="text-2xl font-bold font-mono">{format_r(@correlation["pearson_r"])}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">R&sup2;</div>
            <div class="text-2xl font-bold font-mono">{format_r_squared(@correlation["pearson_r"])}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Strength</div>
            <% {strength_label, strength_class} = correlation_strength(@correlation["pearson_r"]) %>
            <div class={"text-xl font-bold #{strength_class}"}>{strength_label}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Direction</div>
            <div class="text-lg">{correlation_direction(@correlation["pearson_r"])}</div>
          </div>
        </div>

        <%!-- Trend Comparison Summary --%>
        <div class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-3">Trend Comparison</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 text-sm">
            <div>
              <h3 class="font-medium text-base-content/60 mb-2">{vehicle_label(@vehicle)}</h3>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <span class="text-base-content/40">Data Points</span>
                  <div class="font-mono">{length(@vehicle_prices)}</div>
                </div>
                <div>
                  <span class="text-base-content/40">Price Range</span>
                  <div class="font-mono">
                    {format_price(Enum.min_by(@vehicle_prices, & &1.price_cents, fn -> nil end) && Enum.min_by(@vehicle_prices, & &1.price_cents).price_cents)}
                    &ndash;
                    {format_price(Enum.max_by(@vehicle_prices, & &1.price_cents, fn -> nil end) && Enum.max_by(@vehicle_prices, & &1.price_cents).price_cents)}
                  </div>
                </div>
              </div>
            </div>
            <div>
              <h3 class="font-medium text-base-content/60 mb-2">{instrument_label(@instrument)}</h3>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <span class="text-base-content/40">Data Points</span>
                  <div class="font-mono">{length(@instrument_prices)}</div>
                </div>
                <div>
                  <span class="text-base-content/40">Price Range</span>
                  <div class="font-mono">
                    {format_price(Enum.min_by(@instrument_prices, & &1.close_cents, fn -> nil end) && Enum.min_by(@instrument_prices, & &1.close_cents).close_cents)}
                    &ndash;
                    {format_price(Enum.max_by(@instrument_prices, & &1.close_cents, fn -> nil end) && Enum.max_by(@instrument_prices, & &1.close_cents).close_cents)}
                  </div>
                </div>
              </div>
            </div>
          </div>
          <div class="mt-4 p-3 bg-base-200 rounded text-sm">
            <% r = @correlation["pearson_r"] %>
            <p :if={r}>
              The correlation of <strong>{format_r(r)}</strong> between
              <strong>{vehicle_label(@vehicle)}</strong> and <strong>{instrument_label(@instrument)}</strong>
              suggests a
              <strong>{elem(correlation_strength(r), 0) |> String.downcase()}</strong>,
              <strong>{if r > 0, do: "positive", else: "negative"}</strong> relationship.
              <%= cond do %>
                <% abs(r) >= 0.6 -> %>
                  Price movements in these assets tend to track each other meaningfully.
                <% abs(r) >= 0.3 -> %>
                  There is some connection, but many other factors are at play.
                <% true -> %>
                  These assets appear to move largely independently.
              <% end %>
            </p>
          </div>
        </div>

        <%!-- Dual-Axis Chart --%>
        <div :if={@chart_data} class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-4">Price History Comparison</h2>
          <div
            id="cross-chart"
            phx-hook="CrossChart"
            phx-update="ignore"
            data-vehicle={Jason.encode!(@chart_data.vehicle)}
            data-instrument={Jason.encode!(@chart_data.instrument)}
            data-vehicle-label={vehicle_label(@vehicle)}
            data-instrument-label={instrument_label(@instrument)}
            class="h-80"
          >
            <canvas></canvas>
          </div>
          <div class="mt-2 text-xs text-base-content/40">
            Dual Y-axis: vehicle price (left, blue) vs instrument price (right, orange)
          </div>
        </div>

        <%!-- Additional Correlation Stats --%>
        <div :if={@correlation["sample_size"]} class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-3">Correlation Details</h2>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Sample Size</span>
              <div class="font-mono">{@correlation["sample_size"]} pairs</div>
            </div>
            <div :if={@correlation["p_value"]}>
              <span class="text-base-content/60">P-value</span>
              <div class="font-mono">{format_r(@correlation["p_value"])}</div>
            </div>
            <div :if={@correlation["covariance"]}>
              <span class="text-base-content/60">Covariance</span>
              <div class="font-mono">{format_r(@correlation["covariance"])}</div>
            </div>
            <div :if={@correlation["mean_a"]}>
              <span class="text-base-content/60">Mean A / Mean B</span>
              <div class="font-mono">{format_r(@correlation["mean_a"])} / {format_r(@correlation["mean_b"])}</div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Empty State --%>
      <div :if={!@correlation && !@loading && (@selected_vehicle_id || @selected_instrument_id)} class="text-center py-12 text-base-content/40">
        <p class="text-lg">Select both a vehicle and an instrument to compare their price histories.</p>
      </div>

      <div :if={!@selected_vehicle_id && !@selected_instrument_id} class="text-center py-12 text-base-content/40">
        <p class="text-lg">Choose a vehicle and a financial instrument above to begin cross-asset analysis.</p>
      </div>
    </div>
    """
  end
end
