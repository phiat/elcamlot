defmodule Elcamlot.Workers.CryptoBarWorker do
  @moduledoc """
  Oban cron worker that fetches recent crypto bars every 15 minutes.
  Crypto markets run 24/7 so this always has data.

  Fetches 15-minute bars for configured symbols and upserts into price_bars.
  Uses ON CONFLICT DO NOTHING for safe idempotent polling.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Elcamlot.{Alpaca, Markets}

  @symbols ~w(BTC/USD ETH/USD)
  @timeframe_api "15Min"
  @timeframe_db "15Min"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    results =
      Enum.map(@symbols, fn symbol ->
        case fetch_and_store(symbol) do
          {:ok, count} ->
            if count > 0, do: Logger.info("CryptoBarWorker: #{symbol} — #{count} new bars")
            {symbol, :ok, count}

          {:error, reason} ->
            Logger.warning("CryptoBarWorker: #{symbol} failed — #{inspect(reason)}")
            {symbol, :error, reason}
        end
      end)

    errors = Enum.filter(results, fn {_, status, _} -> status == :error end)

    if errors == [] do
      :ok
    else
      # Return ok anyway — we don't want retries to hammer the API.
      # Errors are logged for visibility.
      :ok
    end
  end

  defp fetch_and_store(symbol) do
    with {:ok, instrument} <- ensure_instrument(symbol),
         {:ok, bars} <- Alpaca.fetch_crypto_bars(symbol, timeframe: @timeframe_api, limit: 10) do
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
    # Crypto symbols use "/" (BTC/USD) — store as-is
    case Markets.get_instrument_by_symbol(symbol) do
      nil ->
        Markets.upsert_instrument(%{symbol: symbol, asset_class: "crypto"})

      instrument ->
        {:ok, instrument}
    end
  end
end
