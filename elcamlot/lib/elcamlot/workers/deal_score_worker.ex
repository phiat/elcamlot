defmodule Elcamlot.Workers.DealScoreWorker do
  @moduledoc """
  Oban worker that computes and records deal scores for all vehicles
  with recent price snapshots. Runs daily via cron.

  For each vehicle with snapshots in the last 7 days:
    1. Get the latest price snapshot
    2. Get all market prices for that vehicle
    3. Call OCaml analytics /deal-score endpoint
    4. Record the result as a DealScore record
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger
  alias Elcamlot.{Repo, Vehicles, Analytics}
  alias Elcamlot.Vehicles.{Vehicle, PriceSnapshot}

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    vehicles = vehicles_with_recent_snapshots()

    Logger.info("DealScoreWorker: scoring #{length(vehicles)} vehicles")

    results =
      Enum.map(vehicles, fn vehicle ->
        case score_vehicle(vehicle) do
          {:ok, _deal_score} ->
            :ok

          {:error, reason} ->
            Logger.warning("DealScoreWorker: failed to score vehicle #{vehicle.id}: #{inspect(reason)}")
            :error
        end
      end)

    ok_count = Enum.count(results, &(&1 == :ok))
    err_count = Enum.count(results, &(&1 == :error))

    Logger.info("DealScoreWorker: completed — #{ok_count} scored, #{err_count} failed")
    :ok
  end

  defp vehicles_with_recent_snapshots do
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    from(v in Vehicle,
      join: p in PriceSnapshot,
      on: p.vehicle_id == v.id,
      where: p.time >= ^seven_days_ago,
      distinct: v.id
    )
    |> Repo.all()
  end

  defp score_vehicle(vehicle) do
    market_prices = Vehicles.get_market_prices(vehicle.id)

    if length(market_prices) < 3 do
      {:error, :insufficient_data}
    else
      # Use the most recent snapshot price (first in desc order)
      latest_snapshot =
        from(p in PriceSnapshot,
          where: p.vehicle_id == ^vehicle.id,
          order_by: [desc: p.time],
          limit: 1
        )
        |> Repo.one()

      vehicle_price = latest_snapshot.price_cents
      market_avg = div(Enum.sum(market_prices), length(market_prices))

      case Analytics.deal_score(vehicle_price, market_prices) do
        {:ok, result} ->
          Vehicles.record_deal_score(vehicle, %{
            score: result["score"] || 0.0,
            percentile_rank: result["percentile_rank"],
            market_avg_cents: market_avg,
            vehicle_price_cents: vehicle_price
          })

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
