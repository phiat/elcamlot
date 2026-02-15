defmodule ElcamlotWeb.SearchLive do
  use ElcamlotWeb, :live_view

  alias Elcamlot.{Vehicles, BraveSearch}

  @impl true
  def mount(_params, _session, socket) do
    vehicles = Vehicles.list_vehicles()
    makes = Vehicles.list_makes()

    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:result_count, 0)
     |> assign(:vehicle_count, length(vehicles))
     |> assign(:makes, makes)
     |> assign(:active_make, nil)
     |> stream(:results, [])
     |> stream(:vehicles, vehicles)
     |> assign(:searching, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) when byte_size(query) > 0 do
    socket = assign(socket, searching: true, error: nil, query: query)
    send(self(), {:do_search, query})
    {:noreply, socket}
  end

  def handle_event("search", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("search-db", %{"term" => term}, socket) do
    vehicles = if term == "", do: Vehicles.list_vehicles(), else: Vehicles.search_vehicles(term)

    {:noreply,
     socket
     |> assign(:vehicle_count, length(vehicles))
     |> assign(:active_make, nil)
     |> stream(:vehicles, vehicles, reset: true)}
  end

  def handle_event("filter-make", %{"make" => make}, socket) do
    {active_make, vehicles} =
      if socket.assigns.active_make == make do
        {nil, Vehicles.list_vehicles()}
      else
        {make, Vehicles.list_vehicles_by_make(make)}
      end

    {:noreply,
     socket
     |> assign(:active_make, active_make)
     |> assign(:vehicle_count, length(vehicles))
     |> stream(:vehicles, vehicles, reset: true)}
  end

  @impl true
  def handle_info({:do_search, query}, socket) do
    case BraveSearch.search_cars(query) do
      {:ok, results} ->
        saved = save_results(query, results)

        # Add unique IDs for stream
        results_with_ids =
          results
          |> Enum.with_index()
          |> Enum.map(fn {r, idx} -> Map.put(r, :id, "result-#{idx}-#{:erlang.phash2(r.url)}") end)

        vehicles = Vehicles.list_vehicles()
        makes = Vehicles.list_makes()

        {:noreply,
         socket
         |> assign(:result_count, length(results))
         |> stream(:results, results_with_ids, reset: true)
         |> assign(:vehicle_count, length(vehicles))
         |> assign(:makes, makes)
         |> assign(:active_make, nil)
         |> stream(:vehicles, vehicles, reset: true)
         |> assign(:searching, false)
         |> put_flash(:info, "Found #{length(results)} listings, saved #{saved} prices")}

      {:error, :missing_api_key} ->
        {:noreply,
         socket
         |> assign(:searching, false)
         |> assign(:error, "Brave Search API key not configured. Set BRAVE_SEARCH_API_KEY in .env")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:searching, false)
         |> assign(:error, "Search failed: #{inspect(reason)}")}
    end
  end

  defp save_results(query, results) do
    Vehicles.log_search(query, length(results))

    case parse_vehicle_from_query(query) do
      {:ok, vehicle} ->
        Enum.count(results, fn result ->
          match?({:ok, _},
            Vehicles.create_price_snapshot(%{
              time: DateTime.utc_now(),
              vehicle_id: vehicle.id,
              price_cents: result.price_cents,
              mileage: result.mileage,
              source: result.source,
              url: result.url
            })
          )
        end)

      _ ->
        0
    end
  end


  defp parse_vehicle_from_query(query) do
    case Regex.run(~r/(\d{4})\s+(\w+)\s+(\w+)/i, query) do
      [_, year, make, model] ->
        Vehicles.find_or_create_vehicle(%{
          year: String.to_integer(year),
          make: String.capitalize(make),
          model: String.capitalize(model)
        })

      _ ->
        {:error, :unparseable}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold mb-2">Elcamlot</h1>
          <p class="text-base-content/60">Search for vehicles, track prices, find deals.</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/watchlist"} class="bg-base-200 hover:bg-base-300 text-base-content/80 px-4 py-2 rounded-md text-sm">
            Watchlist
          </.link>
          <.link navigate={~p"/finance"} class="bg-base-200 hover:bg-base-300 text-base-content/80 px-4 py-2 rounded-md text-sm">
            Finance
          </.link>
          <.link navigate={~p"/market"} class="bg-base-200 hover:bg-base-300 text-base-content/80 px-4 py-2 rounded-md text-sm">
            Market Analytics
          </.link>
        </div>
      </div>

      <%!-- Brave Search (collapsed by default) --%>
      <div class="bg-base-100 rounded-lg shadow mb-8">
        <button
          phx-click={JS.toggle(to: "#web-search-body") |> JS.toggle(to: "#web-search-arrow-down") |> JS.toggle(to: "#web-search-arrow-right")}
          class="w-full flex items-center justify-between p-4 cursor-pointer"
        >
          <h2 class="text-lg font-semibold">Search the Web</h2>
          <span id="web-search-arrow-right" class="text-base-content/40">&#9654;</span>
          <span id="web-search-arrow-down" class="text-base-content/40 hidden">&#9660;</span>
        </button>
        <div id="web-search-body" class="hidden px-6 pb-6">
          <.form for={%{}} phx-submit="search" class="flex gap-3">
            <input
              type="text"
              name="query"
              value={@query}
              placeholder="e.g. 2021 Toyota Camry"
              class="flex-1 rounded-md border border-base-300 px-4 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
            />
            <button
              type="submit"
              disabled={@searching}
              class="bg-primary text-primary-content px-6 py-2 rounded-md hover:bg-primary/80 disabled:opacity-50"
            >
              <%= if @searching, do: "Searching...", else: "Search" %>
            </button>
          </.form>

          <%= if @error do %>
            <div class="mt-4 p-3 bg-error/10 text-error rounded">{@error}</div>
          <% end %>

          <%= if @result_count > 0 do %>
            <div class="mt-6">
              <h3 class="font-medium mb-3">Results ({@result_count} with prices)</h3>
              <div id="search-results" class="space-y-3" phx-update="stream">
                <div :for={{dom_id, result} <- @streams.results} id={dom_id} class="border rounded p-3">
                  <div class="flex justify-between">
                    <a href={result.url} target="_blank" class="text-primary hover:underline font-medium">
                      {result.title}
                    </a>
                    <span class="text-success font-bold">
                      ${div(result.price_cents, 100) |> Integer.to_string() |> format_number()}
                    </span>
                  </div>
                  <p class="text-sm text-base-content/60 mt-1">{result.description}</p>
                  <div class="text-xs text-base-content/40 mt-1">
                    Source: {result.source}
                    <%= if result.mileage do %>
                      · {result.mileage |> Integer.to_string() |> format_number()} mi
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Vehicle Database --%>
      <div class="bg-base-100 rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Vehicles ({@vehicle_count})</h2>

        <div class="flex flex-wrap gap-2 mb-4">
          <button
            :for={make <- @makes}
            phx-click="filter-make"
            phx-value-make={make}
            class={[
              "px-3 py-1 rounded-full text-sm font-medium transition-colors",
              if(@active_make == make,
                do: "bg-primary text-primary-content",
                else: "bg-base-200 text-base-content/70 hover:bg-base-300")
            ]}
          >
            {make}
          </button>
        </div>

        <.form for={%{}} phx-change="search-db" class="mb-4">
          <input
            type="text"
            name="term"
            placeholder="Filter by make or model..."
            class="w-full rounded-md border border-base-300 px-4 py-2"
            phx-debounce="200"
          />
        </.form>

        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b text-left text-base-content/60">
                <th class="py-2 pr-2">Vehicle</th>
                <th class="py-2 pr-2 text-right">Avg Price</th>
                <th class="py-2 pr-2 text-right">Pts</th>
                <th class="py-2 pr-2 text-right hidden sm:table-cell">Updated</th>
                <th class="py-2 w-8"></th>
              </tr>
            </thead>
            <tbody id="vehicles-table" phx-update="stream">
              <tr :for={{dom_id, vehicle} <- @streams.vehicles} id={dom_id} class="border-b hover:bg-base-200">
                <td class="py-2 pr-2">
                  <.link navigate={~p"/vehicle/#{vehicle.id}"} class="hover:text-primary">
                    <span class="font-medium">{vehicle.year} {vehicle.make} {vehicle.model}</span>
                    <span :if={vehicle.trim} class="text-base-content/40 text-xs ml-1">{vehicle.trim}</span>
                  </.link>
                </td>
                <td class="py-2 pr-2 text-right font-mono">
                  <%= if vehicle.avg_price do %>
                    <span class="text-success font-bold">{format_price(vehicle.avg_price)}</span>
                  <% else %>
                    <span class="text-base-content/30">—</span>
                  <% end %>
                </td>
                <td class="py-2 pr-2 text-right text-base-content/50">{vehicle.snapshot_count}</td>
                <td class="py-2 pr-2 text-right text-base-content/40 text-xs hidden sm:table-cell">
                  {format_relative_time(vehicle.latest_snapshot_at)}
                </td>
                <td class="py-2 text-center">
                  <.link navigate={~p"/vehicle/#{vehicle.id}"} class="text-primary hover:text-primary/70" title="Dashboard">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 inline" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M2 10a8 8 0 018-8v8h8a8 8 0 11-16 0z" />
                      <path d="M12 2.252A8.014 8.014 0 0117.748 8H12V2.252z" />
                    </svg>
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
