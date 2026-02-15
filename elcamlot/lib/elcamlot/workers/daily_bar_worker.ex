defmodule Elcamlot.Workers.DailyBarWorker do
  @moduledoc """
  Oban cron worker that backfills the latest daily bar for equity instruments.
  Runs once daily after US market close (17:00 ET / 22:00 UTC).

  Only fetches the last 5 days to pick up any bars since the last run,
  using upsert to avoid duplicates. Very conservative API usage (~7 requests).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Elcamlot.{Alpaca, Markets}

  @equity_symbols ~w(AAPL MSFT GOOGL AMZN TSLA SPY QQQ)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    start = Date.utc_today() |> Date.add(-5) |> Date.to_iso8601()

    results =
      Enum.map(@equity_symbols, fn symbol ->
        # Small delay between requests to be polite
        Process.sleep(500)

        case fetch_and_store(symbol, start) do
          {:ok, count} ->
            if count > 0, do: Logger.info("DailyBarWorker: #{symbol} — #{count} new bars")
            {symbol, :ok, count}

          {:error, reason} ->
            Logger.warning("DailyBarWorker: #{symbol} failed — #{inspect(reason)}")
            {symbol, :error, reason}
        end
      end)

    total = Enum.reduce(results, 0, fn
      {_, :ok, count}, acc -> acc + count
      _, acc -> acc
    end)

    ok = Enum.count(results, fn {_, s, _} -> s == :ok end)
    Logger.info("DailyBarWorker: #{ok}/#{length(@equity_symbols)} symbols, #{total} new bars")

    :ok
  end

  defp fetch_and_store(symbol, start) do
    with {:ok, instrument} <- ensure_instrument(symbol),
         {:ok, bars} <- Alpaca.fetch_bars(symbol, start: start, timeframe: "1Day", limit: 10) do
      rows = Enum.map(bars, &Alpaca.bar_to_row(&1, instrument.id, "1D"))

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
