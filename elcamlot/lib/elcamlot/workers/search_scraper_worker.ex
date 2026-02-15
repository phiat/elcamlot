defmodule Elcamlot.Workers.SearchScraperWorker do
  @moduledoc """
  Oban worker that re-runs saved searches on schedule.
  Enqueued by the Oban cron plugin based on saved_search.schedule.
  """
  use Oban.Worker, queue: :scraping, max_attempts: 2

  require Logger
  alias Elcamlot.{Watchlist, Vehicles, BraveSearch}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"saved_search_id" => id}}) do
    search = Watchlist.get_saved_search!(id)

    unless search.active do
      Logger.info("Skipping inactive saved search #{id}")
      :ok
    else
      Logger.info("Running saved search #{id}: #{search.query}")

      case BraveSearch.search_cars(search.query) do
        {:ok, results} ->
          saved = save_search_results(search, results)
          Watchlist.mark_search_run(search, length(results))
          check_price_alerts(search, results)
          Logger.info("Saved search #{id}: #{length(results)} results, #{saved} new snapshots")
          :ok

        {:error, reason} ->
          Logger.warning("Saved search #{id} failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp save_search_results(search, results) do
    case parse_vehicle_from_query(search.query) do
      {:ok, vehicle} ->
        Enum.count(results, fn result ->
          match?({:ok, _},
            Vehicles.create_price_snapshot(%{
              time: DateTime.utc_now(),
              vehicle_id: vehicle.id,
              price_cents: result.price_cents,
              mileage: result.mileage,
              source: result.source,
              url: result.url
            })
          )
        end)

      _ -> 0
    end
  end

  defp check_price_alerts(search, results) do
    case parse_vehicle_from_query(search.query) do
      {:ok, vehicle} ->
        Enum.each(results, fn result ->
          triggered = Watchlist.check_alerts_for_vehicle(vehicle.id, result.price_cents)

          Enum.each(triggered, fn alert ->
            Watchlist.trigger_alert(alert)
            Phoenix.PubSub.broadcast(
              Elcamlot.PubSub,
              "user:#{alert.user_id}:alerts",
              {:price_alert_triggered, alert, vehicle, result.price_cents}
            )
          end)
        end)

      _ -> :ok
    end
  end

  defp parse_vehicle_from_query(query) do
    case Regex.run(~r/(\d{4})\s+(\w+)\s+(\w+)/i, query) do
      [_, year, make, model] ->
        Vehicles.find_or_create_vehicle(%{
          year: String.to_integer(year),
          make: String.capitalize(make),
          model: String.capitalize(model)
        })

      _ ->
        {:error, :unparseable}
    end
  end
end
