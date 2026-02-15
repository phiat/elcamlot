defmodule Elcamlot.Workers.IntradayBackfillWorker do
  @moduledoc """
  One-shot worker to backfill 30 days of 5-minute bars for equity symbols.
  Can be triggered manually via `just backfill-intraday` or enqueued as an Oban job.

  Each symbol produces ~1,950 bars (6.5 hours * 12 bars/hour * 30 days).
  Alpaca returns up to 10,000 bars per request, so one request per symbol suffices.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 3600]

  require Logger
  alias Elcamlot.{Alpaca, Markets}

  @symbols ~w(AAPL MSFT GOOGL AMZN TSLA SPY QQQ)
  @timeframe_api "5Min"
  @timeframe_db "5Min"
  @lookback_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    backfill(@symbols)
  end

  @doc """
  Run backfill directly (for `mix run -e` usage).
  """
  def run(symbols \\ @symbols) do
    backfill(symbols)
  end

  defp backfill(symbols) do
    start = Date.utc_today() |> Date.add(-@lookback_days) |> Date.to_iso8601()
    total_bars = :counters.new(1, [:atomics])

    results =
      Enum.map(symbols, fn symbol ->
        # 1-second delay between symbols to stay well under rate limits
        Process.sleep(1_000)
        Logger.info("IntradayBackfill: Fetching #{@timeframe_api} bars for #{symbol} (#{@lookback_days} days)")

        case fetch_and_store(symbol, start) do
          {:ok, count} ->
            :counters.add(total_bars, 1, count)
            Logger.info("IntradayBackfill: #{symbol} — #{count} bars stored")
            {symbol, :ok, count}

          {:error, reason} ->
            Logger.warning("IntradayBackfill: #{symbol} failed — #{inspect(reason)}")
            {symbol, :error, reason}
        end
      end)

    total = :counters.get(total_bars, 1)
    ok_count = Enum.count(results, fn {_, s, _} -> s == :ok end)
    Logger.info("IntradayBackfill: Complete — #{ok_count}/#{length(symbols)} symbols, #{total} total bars")

    :ok
  end

  defp fetch_and_store(symbol, start) do
    with {:ok, instrument} <- ensure_instrument(symbol),
         {:ok, bars} <- Alpaca.fetch_bars(symbol, start: start, timeframe: @timeframe_api, limit: 10_000) do
      rows = Enum.map(bars, &Alpaca.bar_to_row(&1, instrument.id, @timeframe_db))

      case rows do
        [] -> {:ok, 0}
        rows ->
          {count, _} = Markets.upsert_bars(rows)
          {:ok, count}
      end
    end
  end

  defp ensure_instrument(symbol) do
    case Markets.get_instrument_by_symbol(symbol) do
      nil ->
        Markets.upsert_instrument(%{symbol: symbol, asset_class: "us_equity"})

      instrument ->
        {:ok, instrument}
    end
  end
end
