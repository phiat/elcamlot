defmodule Elcamlot.MarketStatsRefresher do
  @moduledoc """
  Background worker that refreshes the market_stats materialized view hourly.
  """
  use GenServer
  require Logger

  @refresh_interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_refresh()
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    Logger.info("Refreshing market stats materialized view...")

    try do
      Elcamlot.MarketAnalytics.refresh_market_stats()
      Logger.info("Market stats refreshed successfully")
    rescue
      e -> Logger.error("Failed to refresh market stats: #{Exception.message(e)}")
    end

    schedule_refresh()
    {:noreply, state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
