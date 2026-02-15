defmodule Carscope.Repo.Migrations.CreateSavedSearchesAndPriceAlerts do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:saved_searches) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :query, :text, null: false
      add :filters, :map, default: %{}
      add :schedule, :string, default: "daily"
      add :active, :boolean, default: true
      add :last_run_at, :utc_datetime
      add :last_result_count, :integer

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(index(:saved_searches, [:user_id]))
    create_if_not_exists(index(:saved_searches, [:active]))

    create_if_not_exists table(:price_alerts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :vehicle_id, references(:vehicles, on_delete: :delete_all), null: false
      add :target_price_cents, :bigint, null: false
      add :alert_type, :string, null: false, default: "below"
      add :active, :boolean, default: true
      add :triggered_at, :utc_datetime
      add :notified, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(index(:price_alerts, [:user_id]))
    create_if_not_exists(index(:price_alerts, [:vehicle_id]))
    create_if_not_exists(index(:price_alerts, [:active]))
  end
end
