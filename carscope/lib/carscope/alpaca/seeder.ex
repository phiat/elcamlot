defmodule Carscope.Alpaca.Seeder do
  @moduledoc """
  Seeds historical price bar data from Alpaca for instruments.
  """
  require Logger

  alias Carscope.{Markets, Alpaca}

  @doc """
  Seed bars for a symbol. Creates the instrument if it doesn't exist,
  then fetches and inserts historical bars.

  Options:
    - :days - Number of days of history (default: 365)
    - :timeframe - Bar timeframe (default: "1Day")
  """
  def seed(symbol, opts \\ []) do
    symbol = String.upcase(symbol)
    days = Keyword.get(opts, :days, 365)
    timeframe_api = Keyword.get(opts, :timeframe, "1Day")
    timeframe_db = api_to_db_timeframe(timeframe_api)

    Logger.info("Seeding #{symbol}: #{days} days of #{timeframe_api} bars")

    with {:ok, instrument} <- ensure_instrument(symbol),
         {:ok, bars} <- Alpaca.fetch_bars(symbol, start: start_date(days), timeframe: timeframe_api, limit: 10_000) do
      rows = Enum.map(bars, &Alpaca.bar_to_row(&1, instrument.id, timeframe_db))

      case rows do
        [] ->
          Logger.warning("No bars returned for #{symbol}")
          {:ok, 0}

        rows ->
          {count, _} = Markets.insert_bars(rows)
          Logger.info("Inserted #{count} bars for #{symbol}")
          {:ok, count}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to seed #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Seed multiple symbols sequentially."
  def seed_many(symbols, opts \\ []) do
    results =
      Enum.map(symbols, fn symbol ->
        case seed(symbol, opts) do
          {:ok, count} -> {symbol, :ok, count}
          {:error, reason} -> {symbol, :error, reason}
        end
      end)

    ok_count = Enum.count(results, fn {_, status, _} -> status == :ok end)
    total_bars = Enum.reduce(results, 0, fn
      {_, :ok, count}, acc -> acc + count
      _, acc -> acc
    end)

    Logger.info("Seeded #{ok_count}/#{length(symbols)} symbols, #{total_bars} total bars")
    results
  end

  defp ensure_instrument(symbol) do
    case Markets.get_instrument_by_symbol(symbol) do
      nil ->
        Markets.upsert_instrument(%{symbol: symbol, asset_class: "us_equity"})

      instrument ->
        {:ok, instrument}
    end
  end

  defp start_date(days) do
    Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
  end

  defp api_to_db_timeframe("1Min"), do: "1Min"
  defp api_to_db_timeframe("5Min"), do: "5Min"
  defp api_to_db_timeframe("15Min"), do: "15Min"
  defp api_to_db_timeframe("1Hour"), do: "1H"
  defp api_to_db_timeframe("1Day"), do: "1D"
  defp api_to_db_timeframe("1Week"), do: "1W"
  defp api_to_db_timeframe("1Month"), do: "1M"
  defp api_to_db_timeframe(other), do: other
end
