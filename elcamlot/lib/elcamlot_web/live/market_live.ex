defmodule ElcamlotWeb.MarketLive do
  use ElcamlotWeb, :live_view

  require Logger
  alias Elcamlot.MarketAnalytics

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
    e in [Postgrex.Error, DBConnection.ConnectionError] ->
      Logger.debug("Market query failed: #{Exception.message(e)}")
      default
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Market Analytics</h1>
          <p class="text-base-content/60 text-sm">
            Last updated: {Calendar.strftime(@last_refresh, "%H:%M:%S")}
          </p>
        </div>
        <.link navigate={~p"/"} class="text-primary hover:underline text-sm">&larr; Back to search</.link>
      </div>

      <%!-- Time range filter --%>
      <div class="bg-base-100 rounded-lg shadow p-4 mb-6">
        <.form for={%{}} phx-change="filter">
          <label class="text-sm font-medium text-base-content/80 mr-2">Time Range</label>
          <select name="days" class="rounded-md border-base-300 text-sm">
            <option value="30" selected={@days_back == 30}>Last 30 days</option>
            <option value="90" selected={@days_back == 90}>Last 90 days</option>
            <option value="180" selected={@days_back == 180}>Last 6 months</option>
            <option value="365" selected={@days_back == 365}>Last year</option>
          </select>
        </.form>
      </div>

      <%!-- Market Overview Table --%>
      <div class="bg-base-100 rounded-lg shadow mb-6">
        <div class="p-6 border-b">
          <h2 class="text-lg font-semibold">Market Overview</h2>
          <p class="text-sm text-base-content/60">Average prices by make/model/year</p>
        </div>

        <%= if @overview_count == 0 do %>
          <div class="p-6 text-base-content/60 text-center">No market data yet. Search for vehicles to build the dataset.</div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-base-200">
                <tr class="text-left text-base-content/70">
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
                <tr :for={{dom_id, item} <- @streams.market_overview} id={dom_id} class="border-t hover:bg-base-200">
                  <td class="py-3 px-6 font-medium">
                    {item["year"]} {item["make"]} {item["model"]}
                  </td>
                  <td class="py-3 px-4">{item["listing_count"]}</td>
                  <td class="py-3 px-4 font-mono">{format_price(item["avg_price"])}</td>
                  <td class="py-3 px-4 font-mono text-success">{format_price(item["min_price"])}</td>
                  <td class="py-3 px-4 font-mono text-error">{format_price(item["max_price"])}</td>
                  <td class="py-3 px-4 font-mono">{format_price(item["median_price"])}</td>
                  <td class="py-3 px-4 font-mono text-base-content/60">{format_price(item["stddev"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <%!-- Activity Metrics --%>
      <div class="bg-base-100 rounded-lg shadow">
        <div class="p-6 border-b">
          <h2 class="text-lg font-semibold">Recent Activity</h2>
          <p class="text-sm text-base-content/60">Daily listing volumes (last 30 days)</p>
        </div>

        <%= if @activity_metrics == [] do %>
          <div class="p-6 text-base-content/60 text-center">No activity data yet.</div>
        <% else %>
          <div class="p-6 space-y-2">
            <% max_listings = Enum.max_by(@activity_metrics, & &1["new_listings"], fn -> %{"new_listings" => 1} end)["new_listings"] %>
            <%= for day <- Enum.take(@activity_metrics, 14) do %>
              <div class="flex items-center gap-4">
                <div class="w-24 text-sm text-base-content/60 font-mono">{day["date"]}</div>
                <div class="flex-1 bg-base-200 rounded-full h-6 relative overflow-hidden">
                  <% width = if max_listings > 0, do: day["new_listings"] / max_listings * 100, else: 0 %>
                  <div class="bg-primary h-full rounded-full" style={"width: #{width}%"} />
                </div>
                <div class="w-20 text-sm text-base-content/70 text-right">{day["new_listings"]} listings</div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
