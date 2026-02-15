defmodule Elcamlot.Repo.Migrations.CreateDealScores do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:deal_scores) do
      add :vehicle_id, references(:vehicles, on_delete: :delete_all), null: false
      add :score, :float, null: false
      add :percentile_rank, :float
      add :market_avg_cents, :bigint
      add :vehicle_price_cents, :bigint
      add :computed_at, :utc_datetime, null: false
    end

    create_if_not_exists index(:deal_scores, [:vehicle_id, :computed_at])
  end
end
