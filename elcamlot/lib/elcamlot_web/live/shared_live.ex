defmodule ElcamlotWeb.SharedLive do
  @moduledoc """
  Read-only shared view of a vehicle dashboard.
  Accessed via a time-limited share token — no authentication required.
  """
  use ElcamlotWeb, :live_view

  alias Elcamlot.Vehicles

  @token_max_age 7 * 24 * 60 * 60

  @impl true
  def mount(%{"id" => id, "token" => token}, _session, socket) do
    case Phoenix.Token.verify(ElcamlotWeb.Endpoint, "share", token, max_age: @token_max_age) do
      {:ok, {:share, token_vehicle_id}} when is_integer(token_vehicle_id) ->
        if to_string(token_vehicle_id) == to_string(id) do
          load_shared_vehicle(socket, id)
        else
          {:ok, invalid_share(socket)}
        end

      {:ok, {:share, token_vehicle_id}} ->
        if to_string(token_vehicle_id) == to_string(id) do
          load_shared_vehicle(socket, id)
        else
          {:ok, invalid_share(socket)}
        end

      _ ->
        {:ok, invalid_share(socket)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:error, "Missing share token.")
     |> assign(:vehicle, nil)
     |> assign(:snapshots, [])
     |> assign(:stats, %{})}
  end

  defp load_shared_vehicle(socket, id) do
    vehicle = Vehicles.get_vehicle!(id)
    snapshots = Vehicles.list_price_snapshots(vehicle.id)
    stats = Vehicles.price_stats(vehicle.id)

    {:ok,
     socket
     |> assign(:vehicle, vehicle)
     |> assign(:snapshots, snapshots)
     |> assign(:stats, stats)
     |> assign(:page_title, "#{vehicle.year} #{vehicle.make} #{vehicle.model}")}
  end

  defp invalid_share(socket) do
    socket
    |> put_flash(:error, "Invalid or expired share link.")
    |> assign(:vehicle, nil)
    |> assign(:snapshots, [])
    |> assign(:stats, %{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <%= if @vehicle do %>
        <div class="mb-2">
          <span class="inline-block px-2 py-0.5 rounded-full text-xs bg-info/10 text-info font-medium">
            Shared View
          </span>
        </div>

        <div class="mt-2 mb-8">
          <h1 class="text-3xl font-bold">
            {@vehicle.year} {@vehicle.make} {@vehicle.model}
          </h1>
          <p :if={@vehicle.trim} class="text-base-content/60">{@vehicle.trim}</p>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Avg Price</div>
            <div class="text-2xl font-bold">{format_price(@stats["avg_price"])}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Median</div>
            <div class="text-2xl font-bold">{format_price(@stats["median"])}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Min Price</div>
            <div class="text-2xl font-bold text-success">{format_price(@stats["min_price"])}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow p-4">
            <div class="text-sm text-base-content/60">Max Price</div>
            <div class="text-2xl font-bold text-error">{format_price(@stats["max_price"])}</div>
          </div>
        </div>

        <%!-- Distribution Stats --%>
        <div :if={@stats["count"] && @stats["count"] > 2} class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-4">Price Distribution</h2>
          <div class="grid grid-cols-2 md:grid-cols-6 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Std Dev</span>
              <div class="font-mono">{format_price(@stats["std_dev"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">IQR</span>
              <div class="font-mono">{format_price(@stats["iqr"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">P10</span>
              <div class="font-mono">{format_price(@stats["p10"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">P25</span>
              <div class="font-mono">{format_price(@stats["p25"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">P75</span>
              <div class="font-mono">{format_price(@stats["p75"])}</div>
            </div>
            <div>
              <span class="text-base-content/60">P90</span>
              <div class="font-mono">{format_price(@stats["p90"])}</div>
            </div>
          </div>
          <div class="mt-2 text-xs text-base-content/40">{@stats["count"]} data points</div>
        </div>

        <%!-- Price Chart --%>
        <div :if={@snapshots != []} class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-4">Price History</h2>
          <div
            id="price-chart"
            phx-hook="PriceChart"
            phx-update="ignore"
            data-snapshots={Jason.encode!(Enum.map(@snapshots, fn s -> %{time: s.time, price: div(s.price_cents, 100)} end))}
            class="h-64"
          >
            <canvas></canvas>
          </div>
        </div>

        <%!-- Price Table --%>
        <div :if={@snapshots != []} class="bg-base-100 rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold mb-4">Recent Snapshots</h2>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b text-left text-base-content/60">
                  <th class="py-2 pr-4">Date</th>
                  <th class="py-2 pr-4">Price</th>
                  <th class="py-2 pr-4">Mileage</th>
                  <th class="py-2">Source</th>
                </tr>
              </thead>
              <tbody>
                <%= for snap <- Enum.take(@snapshots, 25) do %>
                  <tr class="border-b hover:bg-base-200">
                    <td class="py-2 pr-4 text-base-content/60">{format_date(snap.time)}</td>
                    <td class="py-2 pr-4 font-mono font-bold">{format_price(snap.price_cents)}</td>
                    <td class="py-2 pr-4">
                      <%= if snap.mileage do %>
                        {snap.mileage |> Integer.to_string() |> format_number()} mi
                      <% else %>
                        ---
                      <% end %>
                    </td>
                    <td class="py-2">{snap.source || "---"}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div class="text-center text-sm text-base-content/40 mt-12 mb-4">
          Shared from Elcamlot &middot; Data is read-only
        </div>
      <% else %>
        <div class="text-center py-20">
          <h1 class="text-2xl font-bold mb-4">Link Unavailable</h1>
          <p class="text-base-content/60 mb-6">This share link is invalid or has expired.</p>
          <.link navigate={~p"/users/log-in"} class="text-primary hover:underline">
            Log in to Elcamlot
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

end
