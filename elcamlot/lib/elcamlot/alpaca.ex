defmodule Elcamlot.Alpaca do
  @moduledoc """
  Wrapper around alpa_ex SDK for fetching market data from Alpaca.
  """
  require Logger

  @doc """
  Fetch historical bars for a symbol.
  Returns {:ok, [%Alpa.Models.Bar{}, ...]} or {:error, reason}.
  """
  def fetch_bars(symbol, opts \\ []) do
    config = config()

    case Alpa.bars(symbol, Keyword.merge(default_bar_opts(), opts) ++ [config: config]) do
      {:ok, bars} ->
        {:ok, bars}

      {:error, %Alpa.Error{} = err} ->
        Logger.warning("Alpaca bars error for #{symbol}: #{inspect(err)}")
        {:error, err}

      {:error, reason} ->
        Logger.error("Alpaca bars failed for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch the latest snapshot (quote + bar) for a symbol.
  """
  def fetch_snapshot(symbol) do
    config = config()

    case Alpa.snapshot(symbol, config: config) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} ->
        Logger.warning("Alpaca snapshot error for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch historical bars for a crypto symbol (e.g., "BTC/USD").
  Uses the crypto market data API which is available 24/7.
  """
  def fetch_crypto_bars(symbol, opts \\ []) do
    config = config()

    case Alpa.crypto_bars(symbol, Keyword.merge(default_crypto_bar_opts(), opts) ++ [config: config]) do
      {:ok, bars} ->
        {:ok, bars}

      {:error, %Alpa.Error{} = err} ->
        Logger.warning("Alpaca crypto bars error for #{symbol}: #{inspect(err)}")
        {:error, err}

      {:error, reason} ->
        Logger.error("Alpaca crypto bars failed for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch the latest bar for a crypto symbol.
  """
  def fetch_crypto_latest(symbol) do
    config = config()

    case Alpa.crypto_latest_bars(symbol, config: config) do
      {:ok, [bar | _]} -> {:ok, bar}
      {:ok, []} -> {:error, :no_data}
      {:error, reason} ->
        Logger.warning("Alpaca crypto latest error for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch available assets from Alpaca.
  """
  def list_assets(opts \\ []) do
    config = config()
    Alpa.assets(Keyword.merge([status: "active", asset_class: "us_equity"], opts) ++ [config: config])
  end

  @doc """
  Convert an Alpa.Models.Bar to a map suitable for insert_all.
  Prices are stored in cents (integer).
  """
  def bar_to_row(%{} = bar, instrument_id, timeframe \\ "1D") do
    %{
      time: bar.timestamp,
      instrument_id: instrument_id,
      open_cents: decimal_to_cents(bar.open),
      high_cents: decimal_to_cents(bar.high),
      low_cents: decimal_to_cents(bar.low),
      close_cents: decimal_to_cents(bar.close),
      volume: to_integer_volume(bar.volume),
      timeframe: timeframe
    }
  end

  # --- Private ---

  defp to_integer_volume(nil), do: 0
  defp to_integer_volume(v) when is_integer(v), do: v
  defp to_integer_volume(v) when is_float(v), do: round(v)
  defp to_integer_volume(%Decimal{} = v), do: v |> Decimal.round(0) |> Decimal.to_integer()

  defp decimal_to_cents(%Decimal{} = d) do
    d |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
  end

  defp decimal_to_cents(n) when is_float(n), do: round(n * 100)
  defp decimal_to_cents(n) when is_integer(n), do: n * 100

  defp default_crypto_bar_opts do
    [
      timeframe: "15Min",
      start: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_iso8601(),
      limit: 10
    ]
  end

  defp default_bar_opts do
    [
      timeframe: "1Day",
      start: Date.utc_today() |> Date.add(-365) |> Date.to_iso8601(),
      limit: 1000
    ]
  end

  defp config do
    Alpa.Config.new(
      api_key: api_key(),
      api_secret: api_secret(),
      use_paper: true
    )
  end

  defp api_key, do: Application.get_env(:elcamlot, :alpaca_api_key, System.get_env("APCA_API_KEY_ID", ""))
  defp api_secret, do: Application.get_env(:elcamlot, :alpaca_api_secret, System.get_env("APCA_API_SECRET_KEY", ""))
end
