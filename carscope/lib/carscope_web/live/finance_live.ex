defmodule CarscopeWeb.FinanceLive do
  use CarscopeWeb, :live_view

  alias Carscope.Markets

  @impl true
  def mount(_params, _session, socket) do
    instruments = Markets.list_instruments()

    {:ok,
     socket
     |> assign(:instruments, instruments)
     |> assign(:query, "")}
  end

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    filtered =
      if query == "" do
        Markets.list_instruments()
      else
        q = String.upcase(query)

        Markets.list_instruments()
        |> Enum.filter(fn i ->
          String.contains?(i.symbol, q) ||
            (i.name && String.contains?(String.upcase(i.name), q))
        end)
      end

    {:noreply, assign(socket, instruments: filtered, query: query)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Financial Instruments</h1>

      <div class="mb-6">
        <form phx-change="filter" phx-submit="filter">
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search symbols..."
            phx-debounce="200"
            class="input input-bordered w-full max-w-sm"
          />
        </form>
      </div>

      <%= if @instruments == [] do %>
        <div class="bg-base-100 rounded-lg shadow p-8 text-center">
          <p class="text-base-content/60 mb-4">No instruments yet.</p>
          <p class="text-sm text-base-content/40">
            Seed data with: <code class="bg-base-200 px-2 py-1 rounded">just alpaca-seed AAPL</code>
          </p>
        </div>
      <% else %>
        <div class="bg-base-100 rounded-lg shadow overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b text-left text-base-content/60 bg-base-200/50">
                <th class="py-3 px-4">Symbol</th>
                <th class="py-3 px-4">Name</th>
                <th class="py-3 px-4">Class</th>
                <th class="py-3 px-4">Exchange</th>
                <th class="py-3 px-4">Status</th>
                <th class="py-3 px-4"></th>
              </tr>
            </thead>
            <tbody>
              <%= for instrument <- @instruments do %>
                <tr class="border-b hover:bg-base-200/30">
                  <td class="py-3 px-4 font-mono font-bold">{instrument.symbol}</td>
                  <td class="py-3 px-4">{instrument.name || "—"}</td>
                  <td class="py-3 px-4">
                    <span class="px-2 py-0.5 rounded-full text-xs bg-primary/10 text-primary">
                      {instrument.asset_class}
                    </span>
                  </td>
                  <td class="py-3 px-4 text-base-content/60">{instrument.exchange || "—"}</td>
                  <td class="py-3 px-4">
                    <span class={[
                      "px-2 py-0.5 rounded-full text-xs",
                      if(instrument.status == "active", do: "bg-success/10 text-success", else: "bg-base-200 text-base-content/40")
                    ]}>
                      {instrument.status}
                    </span>
                  </td>
                  <td class="py-3 px-4">
                    <.link navigate={~p"/finance/#{instrument.id}"} class="text-primary hover:underline text-sm">
                      Dashboard &rarr;
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
        <div class="mt-3 text-sm text-base-content/40">{length(@instruments)} instruments</div>
      <% end %>
    </div>
    """
  end
end
