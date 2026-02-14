defmodule Carscope.Analytics do
  @moduledoc """
  Client for the OxCaml analytics service.

  Sends price data to the OCaml service for statistical analysis,
  deal scoring, and depreciation curve fitting.
  """
  require Logger

  @doc """
  Analyze price data for a vehicle. Sends prices to OCaml service
  and returns statistics + deal score.
  """
  def analyze_prices(prices_cents) when is_list(prices_cents) do
    payload = %{prices: prices_cents}

    case post("/analyze", payload) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a deal score for a specific price given market data.
  Returns a score from 0-100 (100 = best deal).
  """
  def deal_score(price_cents, market_prices) do
    payload = %{price: price_cents, market_prices: market_prices}

    case post("/deal-score", payload) do
      {:ok, %{"score" => score}} -> {:ok, score}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calculate depreciation curve for a vehicle given price history.
  Returns curve parameters and predicted future values.
  """
  def depreciation(price_history) do
    payload = %{
      history:
        Enum.map(price_history, fn %{time: time, price_cents: price} ->
          %{time: DateTime.to_iso8601(time), price: price}
        end)
    }

    case post("/depreciation", payload) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Health check for the analytics service."
  def healthy? do
    case Req.get(client(), url: "/health") do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  # --- Private ---

  defp client do
    Req.new(
      base_url: base_url(),
      retry: :transient,
      retry_delay: fn attempt -> 100 * Integer.pow(2, attempt) end,
      max_retries: 3,
      receive_timeout: 5_000
    )
  end

  defp post(path, body) do
    case Req.post(client(), url: path, json: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Analytics service returned #{status}: #{inspect(body)}")
        {:error, {:service_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("Analytics service timed out for #{path}")
        {:error, {:timeout, path}}

      {:error, reason} ->
        Logger.error("Analytics service unavailable: #{inspect(reason)}")
        {:error, {:unavailable, reason}}
    end
  end

  defp base_url do
    Application.get_env(:carscope, :analytics_url, "http://localhost:8080")
  end
end
