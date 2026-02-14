defmodule Carscope.BraveSearch.Throttler do
  @moduledoc """
  GenServer-based API quota tracker for Brave Search.
  Tracks monthly request count and rejects when quota exhausted.
  """
  use GenServer
  require Logger

  @monthly_limit 2000
  @search_rate_limit 10
  @search_window_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Request permission to make a search. Returns :ok or {:error, reason}."
  def request_search do
    GenServer.call(__MODULE__, :request_search, 30_000)
  end

  @doc "Check remaining monthly quota."
  def quota_remaining do
    GenServer.call(__MODULE__, :quota_remaining)
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    {:ok, %{month: current_month(), count: 0}}
  end

  @impl true
  def handle_call(:request_search, _from, state) do
    state = maybe_reset_month(state)

    cond do
      state.count >= @monthly_limit ->
        Logger.warning("Brave Search monthly quota exhausted (#{state.count}/#{@monthly_limit})")
        {:reply, {:error, :quota_exceeded}, state}

      true ->
        # Per-minute rate limit using Hammer (keyed by :global since it's one API key)
        case Hammer.check_rate("brave_search:global", @search_window_ms, @search_rate_limit) do
          {:allow, _} ->
            {:reply, :ok, %{state | count: state.count + 1}}

          {:deny, _} ->
            {:reply, {:error, :rate_limited}, state}
        end
    end
  end

  def handle_call(:quota_remaining, _from, state) do
    state = maybe_reset_month(state)
    {:reply, @monthly_limit - state.count, state}
  end

  defp maybe_reset_month(%{month: month} = state) do
    current = current_month()
    if current != month, do: %{state | month: current, count: 0}, else: state
  end

  defp current_month do
    Date.utc_today() |> Date.beginning_of_month()
  end
end
