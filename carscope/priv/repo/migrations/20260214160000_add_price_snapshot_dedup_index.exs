defmodule Carscope.Repo.Migrations.AddPriceSnapshotDedupIndex do
  use Ecto.Migration

  def change do
    # Prevent duplicate listings: same URL + vehicle + same day
    create unique_index(:price_snapshots, [
      :vehicle_id,
      :url,
      "CAST(time AS date)"
    ], name: :price_snapshots_vehicle_url_date_idx)
  end
end
