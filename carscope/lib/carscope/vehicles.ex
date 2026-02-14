defmodule Carscope.Vehicles do
  @moduledoc """
  Context for vehicle data and price tracking.
  """
  import Ecto.Query
  alias Carscope.Repo
  alias Carscope.Vehicles.{Vehicle, PriceSnapshot, SearchQuery}

  # --- Vehicles ---

  def list_vehicles do
    Repo.all(from v in Vehicle, order_by: [asc: v.make, asc: v.model, desc: v.year])
  end

  def get_vehicle!(id), do: Repo.get!(Vehicle, id)

  def find_or_create_vehicle(attrs) do
    query =
      from v in Vehicle,
        where: v.make == ^attrs.make and v.model == ^attrs.model and v.year == ^attrs.year

    query =
      if attrs[:trim],
        do: from(v in query, where: v.trim == ^attrs.trim),
        else: query

    case Repo.one(query) do
      nil -> create_vehicle(attrs)
      vehicle -> {:ok, vehicle}
    end
  end

  def create_vehicle(attrs) do
    %Vehicle{}
    |> Vehicle.changeset(attrs)
    |> Repo.insert()
  end

  def search_vehicles(term) do
    like = "%#{term}%"

    from(v in Vehicle,
      where: ilike(v.make, ^like) or ilike(v.model, ^like),
      order_by: [desc: v.year],
      limit: 50
    )
    |> Repo.all()
  end

  # --- Price Snapshots ---

  def list_price_snapshots(vehicle_id) do
    from(p in PriceSnapshot,
      where: p.vehicle_id == ^vehicle_id,
      order_by: [desc: p.time]
    )
    |> Repo.all()
  end

  def create_price_snapshot(attrs) do
    %PriceSnapshot{}
    |> PriceSnapshot.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  def get_market_prices(vehicle_id) do
    from(p in PriceSnapshot,
      where: p.vehicle_id == ^vehicle_id,
      select: p.price_cents
    )
    |> Repo.all()
  end

  def price_stats(vehicle_id) do
    from(p in PriceSnapshot,
      where: p.vehicle_id == ^vehicle_id,
      select: %{
        count: count(p.price_cents),
        avg_price: avg(p.price_cents),
        min_price: min(p.price_cents),
        max_price: max(p.price_cents),
        latest: max(p.time)
      }
    )
    |> Repo.one()
  end

  def price_trends(vehicle_id, time_bucket \\ "1 day") do
    query = """
    SELECT
      time_bucket($1::interval, time) AS bucket,
      AVG(price_cents) AS avg_price,
      MIN(price_cents) AS min_price,
      MAX(price_cents) AS max_price,
      COUNT(*) AS count
    FROM price_snapshots
    WHERE vehicle_id = $2
    GROUP BY bucket
    ORDER BY bucket DESC
    """

    Ecto.Adapters.SQL.query!(Repo, query, [time_bucket, vehicle_id])
  end

  # --- Search Queries ---

  def log_search(query, result_count) do
    %SearchQuery{}
    |> SearchQuery.changeset(%{
      query: query,
      result_count: result_count,
      searched_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end
end
