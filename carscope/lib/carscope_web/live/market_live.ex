defmodule CarscopeWeb.MarketLive do
  use CarscopeWeb, :live_view

  alias Carscope.MarketAnalytics

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(300_000, self(), :refresh)

    {:ok, load_data(socket)}
  end

  @impl true
  def handle_event("filter", %{"days" => days}, socket) do
    days_back = String.to_integer(days)
    {:noreply, load_data(socket, days_back)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  defp load_data(socket, days_back \\ 90) do
    overview = safe_query(fn -> MarketAnalytics.market_overview(days_back: days_back) end, [])
    activity = safe_query(fn -> MarketAnalytics.activity_metrics(days_back: 30) end, [])

    # Add IDs for streaming
    overview_with_ids =
      overview
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} -> Map.put(item, "id", "overview-#{idx}") end)

    socket
    |> assign(:overview_count, length(overview))
    |> stream(:market_overview, overview_with_ids, reset: true, dom_id: &(&1["id"]))
    |> assign(:activity_metrics, activity)
    |> assign(:days_back, days_back)
    |> assign(:last_refresh, DateTime.utc_now())
  end

  defp safe_query(fun, default) do
    fun.()
  rescue
    _ -> default
  end

  defp format_price(nil), do: "—"

  defp format_price(cents) when is_number(cents) do
    dollars = trunc(cents / 100)
    "$#{dollars |> Integer.to_string() |> format_number()}"
  end

  defp format_number(str) do
    str
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Market Analytics</h1>
          <p class="text-zinc-500 text-sm">
            Last updated: {Calendar.strftime(@last_refresh, "%H:%M:%S")}
          </p>
        </div>
        <.link navigate={~p"/"} class="text-blue-600 hover:underline text-sm">&larr; Back to search</.link>
      </div>

      <%!-- Time range filter --%>
      <div class="bg-white rounded-lg shadow p-4 mb-6">
        <.form for={%{}} phx-change="filter">
          <label class="text-sm font-medium text-zinc-700 mr-2">Time Range</label>
          <select name="days" class="rounded-md border-zinc-300 text-sm">
            <option value="30" selected={@days_back == 30}>Last 30 days</option>
            <option value="90" selected={@days_back == 90}>Last 90 days</option>
            <option value="180" selected={@days_back == 180}>Last 6 months</option>
            <option value="365" selected={@days_back == 365}>Last year</option>
          </select>
        </.form>
      </div>

      <%!-- Market Overview Table --%>
      <div class="bg-white rounded-lg shadow mb-6">
        <div class="p-6 border-b">
          <h2 class="text-lg font-semibold">Market Overview</h2>
          <p class="text-sm text-zinc-500">Average prices by make/model/year</p>
        </div>

        <%= if @overview_count == 0 do %>
          <div class="p-6 text-zinc-500 text-center">No market data yet. Search for vehicles to build the dataset.</div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-zinc-50">
                <tr class="text-left text-zinc-600">
                  <th class="py-3 px-6">Vehicle</th>
                  <th class="py-3 px-4">Listings</th>
                  <th class="py-3 px-4">Avg Price</th>
                  <th class="py-3 px-4">Min</th>
                  <th class="py-3 px-4">Max</th>
                  <th class="py-3 px-4">Median</th>
                  <th class="py-3 px-4">Std Dev</th>
                </tr>
              </thead>
              <tbody id="market-overview" phx-update="stream">
                <tr :for={{dom_id, item} <- @streams.market_overview} id={dom_id} class="border-t hover:bg-zinc-50">
                  <td class="py-3 px-6 font-medium">
                    {item["year"]} {item["make"]} {item["model"]}
                  </td>
                  <td class="py-3 px-4">{item["listing_count"]}</td>
                  <td class="py-3 px-4 font-mono">{format_price(item["avg_price"])}</td>
                  <td class="py-3 px-4 font-mono text-green-600">{format_price(item["min_price"])}</td>
                  <td class="py-3 px-4 font-mono text-red-600">{format_price(item["max_price"])}</td>
                  <td class="py-3 px-4 font-mono">{format_price(item["median_price"])}</td>
                  <td class="py-3 px-4 font-mono text-zinc-500">{format_price(item["stddev"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <%!-- Activity Metrics --%>
      <div class="bg-white rounded-lg shadow">
        <div class="p-6 border-b">
          <h2 class="text-lg font-semibold">Recent Activity</h2>
          <p class="text-sm text-zinc-500">Daily listing volumes (last 30 days)</p>
        </div>

        <%= if @activity_metrics == [] do %>
          <div class="p-6 text-zinc-500 text-center">No activity data yet.</div>
        <% else %>
          <div class="p-6 space-y-2">
            <% max_listings = Enum.max_by(@activity_metrics, & &1["new_listings"], fn -> %{"new_listings" => 1} end)["new_listings"] %>
            <%= for day <- Enum.take(@activity_metrics, 14) do %>
              <div class="flex items-center gap-4">
                <div class="w-24 text-sm text-zinc-500 font-mono">{day["date"]}</div>
                <div class="flex-1 bg-zinc-100 rounded-full h-6 relative overflow-hidden">
                  <% width = if max_listings > 0, do: day["new_listings"] / max_listings * 100, else: 0 %>
                  <div class="bg-blue-500 h-full rounded-full" style={"width: #{width}%"} />
                </div>
                <div class="w-20 text-sm text-zinc-600 text-right">{day["new_listings"]} listings</div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
