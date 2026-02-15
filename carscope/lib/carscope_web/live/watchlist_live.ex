defmodule CarscopeWeb.WatchlistLive do
  use CarscopeWeb, :live_view

  alias Carscope.Watchlist

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    searches = Watchlist.list_saved_searches(user.id)
    alerts = Watchlist.list_alerts(user.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Carscope.PubSub, "user:#{user.id}:alerts")
    end

    {:ok,
     socket
     |> assign(:searches, searches)
     |> assign(:alerts, alerts)
     |> assign(:show_form, false)
     |> assign(:form, to_form(%{"name" => "", "query" => "", "schedule" => "daily"}))}
  end

  @impl true
  def handle_event("toggle-form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  def handle_event("save-search", %{"name" => name, "query" => query, "schedule" => schedule}, socket) do
    user = socket.assigns.current_scope.user

    case Watchlist.create_saved_search(%{
      name: name,
      query: query,
      schedule: schedule,
      user_id: user.id
    }) do
      {:ok, _search} ->
        searches = Watchlist.list_saved_searches(user.id)

        {:noreply,
         socket
         |> assign(:searches, searches)
         |> assign(:show_form, false)
         |> assign(:form, to_form(%{"name" => "", "query" => "", "schedule" => "daily"}))
         |> put_flash(:info, "Saved search created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create saved search")}
    end
  end

  def handle_event("delete-search", %{"id" => id}, socket) do
    search = Watchlist.get_saved_search!(id)
    Watchlist.delete_saved_search(search)
    user = socket.assigns.current_scope.user
    searches = Watchlist.list_saved_searches(user.id)

    {:noreply,
     socket
     |> assign(:searches, searches)
     |> put_flash(:info, "Search removed")}
  end

  def handle_event("toggle-search", %{"id" => id}, socket) do
    search = Watchlist.get_saved_search!(id)
    Watchlist.update_saved_search(search, %{active: !search.active})
    user = socket.assigns.current_scope.user
    searches = Watchlist.list_saved_searches(user.id)

    {:noreply, assign(socket, searches: searches)}
  end

  def handle_event("run-now", %{"id" => id}, socket) do
    %{saved_search_id: id}
    |> Carscope.Workers.SearchScraperWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Search queued for immediate run")}
  end

  def handle_event("delete-alert", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    alert = Carscope.Repo.get!(Carscope.Watchlist.PriceAlert, id)
    Watchlist.delete_alert(alert)
    alerts = Watchlist.list_alerts(user.id)

    {:noreply,
     socket
     |> assign(:alerts, alerts)
     |> put_flash(:info, "Alert removed")}
  end

  @impl true
  def handle_info({:price_alert_triggered, _alert, vehicle, price_cents}, socket) do
    user = socket.assigns.current_scope.user
    alerts = Watchlist.list_alerts(user.id)

    {:noreply,
     socket
     |> assign(:alerts, alerts)
     |> put_flash(:info, "Price alert triggered for #{vehicle.year} #{vehicle.make} #{vehicle.model}: #{format_price(price_cents)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Watchlist</h1>
          <p class="text-base-content/60">Saved searches and price alerts</p>
        </div>
        <button
          phx-click="toggle-form"
          class="bg-primary text-primary-content px-4 py-2 rounded-md text-sm hover:bg-primary/80"
        >
          + New Search
        </button>
      </div>

      <%!-- New Search Form --%>
      <div :if={@show_form} class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Add Saved Search</h2>
        <.form for={@form} phx-submit="save-search" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label class="text-sm text-base-content/60 block mb-1">Name</label>
              <input type="text" name="name" value={@form[:name].value} placeholder="e.g. My Camry Search" class="input input-bordered w-full" required />
            </div>
            <div>
              <label class="text-sm text-base-content/60 block mb-1">Search Query</label>
              <input type="text" name="query" value={@form[:query].value} placeholder="e.g. 2021 Toyota Camry" class="input input-bordered w-full" required />
            </div>
          </div>
          <div>
            <label class="text-sm text-base-content/60 block mb-1">Schedule</label>
            <select name="schedule" class="select select-bordered w-full max-w-xs">
              <option value="manual">Manual only</option>
              <option value="daily" selected>Daily</option>
              <option value="6hr">Every 6 hours</option>
              <option value="hourly">Hourly</option>
            </select>
          </div>
          <div class="flex gap-2">
            <button type="submit" class="bg-primary text-primary-content px-4 py-2 rounded text-sm">Save</button>
            <button type="button" phx-click="toggle-form" class="bg-base-200 px-4 py-2 rounded text-sm">Cancel</button>
          </div>
        </.form>
      </div>

      <%!-- Saved Searches --%>
      <div class="bg-base-100 rounded-lg shadow p-6 mb-8">
        <h2 class="text-lg font-semibold mb-4">Saved Searches ({length(@searches)})</h2>
        <%= if @searches == [] do %>
          <p class="text-base-content/40 text-sm">No saved searches yet. Click "+ New Search" to add one.</p>
        <% else %>
          <div class="space-y-3">
            <%= for search <- @searches do %>
              <div class="flex items-center gap-4 p-3 rounded-lg bg-base-200/30 hover:bg-base-200/50">
                <div class="flex-1">
                  <div class="font-medium">{search.name}</div>
                  <div class="text-sm text-base-content/60">
                    <code class="bg-base-200 px-1 rounded">{search.query}</code>
                    <span class="ml-2">{schedule_label(search.schedule)}</span>
                  </div>
                  <div :if={search.last_run_at} class="text-xs text-base-content/40 mt-1">
                    Last run: {Calendar.strftime(search.last_run_at, "%b %d %H:%M")}
                    · {search.last_result_count || 0} results
                  </div>
                </div>
                <div class="flex gap-2">
                  <button phx-click="run-now" phx-value-id={search.id}
                    class="px-3 py-1 bg-primary/10 text-primary rounded text-xs hover:bg-primary/20">
                    Run Now
                  </button>
                  <button phx-click="toggle-search" phx-value-id={search.id}
                    class={["px-3 py-1 rounded text-xs",
                      if(search.active, do: "bg-success/10 text-success", else: "bg-base-200 text-base-content/40")]}>
                    {if search.active, do: "Active", else: "Paused"}
                  </button>
                  <button phx-click="delete-search" phx-value-id={search.id}
                    data-confirm="Delete this saved search?"
                    class="px-3 py-1 bg-error/10 text-error rounded text-xs hover:bg-error/20">
                    Delete
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Price Alerts --%>
      <div class="bg-base-100 rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Price Alerts ({length(@alerts)})</h2>
        <%= if @alerts == [] do %>
          <p class="text-base-content/40 text-sm">No price alerts. Set alerts from a vehicle's dashboard page.</p>
        <% else %>
          <div class="space-y-3">
            <%= for alert <- @alerts do %>
              <div class="flex items-center gap-4 p-3 rounded-lg bg-base-200/30">
                <div class="flex-1">
                  <div class="font-medium">
                    {alert.vehicle.year} {alert.vehicle.make} {alert.vehicle.model}
                  </div>
                  <div class="text-sm">
                    <span class={if(alert.alert_type == "below", do: "text-success", else: "text-warning")}>
                      {alert_type_label(alert.alert_type)}
                    </span>
                    <span class="font-mono font-bold ml-1">{format_price(alert.target_price_cents)}</span>
                  </div>
                  <div :if={alert.triggered_at} class="text-xs text-success mt-1">
                    Triggered: {Calendar.strftime(alert.triggered_at, "%b %d %H:%M")}
                  </div>
                </div>
                <span class={["px-2 py-0.5 rounded-full text-xs",
                  if(alert.active, do: "bg-success/10 text-success", else: "bg-base-200 text-base-content/40")]}>
                  {if alert.active, do: "Watching", else: "Triggered"}
                </span>
                <button phx-click="delete-alert" phx-value-id={alert.id}
                  data-confirm="Remove this alert?"
                  class="px-3 py-1 bg-error/10 text-error rounded text-xs">
                  Remove
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp schedule_label("hourly"), do: "Every hour"
  defp schedule_label("6hr"), do: "Every 6 hours"
  defp schedule_label("daily"), do: "Daily"
  defp schedule_label("manual"), do: "Manual"
  defp schedule_label(_), do: "—"

  defp alert_type_label("below"), do: "Alert when below"
  defp alert_type_label("above"), do: "Alert when above"
  defp alert_type_label("pct_drop"), do: "Alert on % drop"
  defp alert_type_label(_), do: "Alert"
end
