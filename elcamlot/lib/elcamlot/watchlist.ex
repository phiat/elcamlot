defmodule Elcamlot.Watchlist do
  @moduledoc """
  Context for saved searches and price alerts.
  """
  import Ecto.Query
  alias Elcamlot.Repo
  alias Elcamlot.Watchlist.{SavedSearch, PriceAlert}

  # --- Saved Searches ---

  def list_saved_searches(user_id) do
    from(s in SavedSearch,
      where: s.user_id == ^user_id,
      order_by: [desc: s.updated_at]
    )
    |> Repo.all()
  end

  def list_active_searches do
    from(s in SavedSearch, where: s.active == true)
    |> Repo.all()
  end

  def list_due_searches(schedule) do
    cutoff = schedule_cutoff(schedule)

    from(s in SavedSearch,
      where: s.active == true and s.schedule == ^schedule,
      where: is_nil(s.last_run_at) or s.last_run_at < ^cutoff
    )
    |> Repo.all()
  end

  def get_saved_search!(id), do: Repo.get!(SavedSearch, id)

  def create_saved_search(attrs) do
    %SavedSearch{}
    |> SavedSearch.changeset(attrs)
    |> Repo.insert()
  end

  def update_saved_search(%SavedSearch{} = search, attrs) do
    search
    |> SavedSearch.changeset(attrs)
    |> Repo.update()
  end

  def delete_saved_search(%SavedSearch{} = search) do
    Repo.delete(search)
  end

  def mark_search_run(%SavedSearch{} = search, result_count) do
    update_saved_search(search, %{
      last_run_at: DateTime.utc_now(),
      last_result_count: result_count
    })
  end

  # --- Price Alerts ---

  def list_alerts(user_id) do
    from(a in PriceAlert,
      where: a.user_id == ^user_id,
      preload: [:vehicle],
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  def list_active_alerts_for_vehicle(vehicle_id) do
    from(a in PriceAlert,
      where: a.vehicle_id == ^vehicle_id and a.active == true,
      preload: [:user]
    )
    |> Repo.all()
  end

  def create_alert(attrs) do
    %PriceAlert{}
    |> PriceAlert.changeset(attrs)
    |> Repo.insert()
  end

  def trigger_alert(%PriceAlert{} = alert) do
    alert
    |> PriceAlert.changeset(%{triggered_at: DateTime.utc_now(), active: false, notified: true})
    |> Repo.update()
  end

  def delete_alert(%PriceAlert{} = alert) do
    Repo.delete(alert)
  end

  def check_alerts_for_vehicle(vehicle_id, new_price_cents) do
    alerts = list_active_alerts_for_vehicle(vehicle_id)

    Enum.filter(alerts, fn alert ->
      case alert.alert_type do
        "below" -> new_price_cents <= alert.target_price_cents
        "above" -> new_price_cents >= alert.target_price_cents
        _ -> false
      end
    end)
  end

  # --- Private ---

  defp schedule_cutoff("hourly"), do: DateTime.add(DateTime.utc_now(), -3600, :second)
  defp schedule_cutoff("6hr"), do: DateTime.add(DateTime.utc_now(), -21600, :second)
  defp schedule_cutoff("daily"), do: DateTime.add(DateTime.utc_now(), -86400, :second)
  defp schedule_cutoff(_), do: DateTime.add(DateTime.utc_now(), -86400, :second)
end
