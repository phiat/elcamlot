defmodule Carscope.Repo.Migrations.CreateInstrumentsAndPriceBars do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:instruments) do
      add :symbol, :string, null: false
      add :name, :string
      add :asset_class, :string, null: false, default: "us_equity"
      add :exchange, :string
      add :status, :string, default: "active"

      timestamps(type: :utc_datetime, updated_at: false, inserted_at: :created_at)
    end

    create_if_not_exists(unique_index(:instruments, [:symbol]))
    create_if_not_exists(index(:instruments, [:asset_class]))

    create_if_not_exists table(:price_bars, primary_key: false) do
      add :time, :utc_datetime, null: false
      add :instrument_id, references(:instruments), null: false
      add :open_cents, :bigint, null: false
      add :high_cents, :bigint, null: false
      add :low_cents, :bigint, null: false
      add :close_cents, :bigint, null: false
      add :volume, :bigint, null: false, default: 0
      add :timeframe, :string, null: false, default: "1D"
    end

    create_if_not_exists(index(:price_bars, [:instrument_id]))
    create_if_not_exists(index(:price_bars, [:timeframe]))

    # Convert to TimescaleDB hypertable
    execute("SELECT create_hypertable('price_bars', 'time', if_not_exists => TRUE)")
  end

  def down do
    drop_if_exists(table(:price_bars))
    drop_if_exists(table(:instruments))
  end
end
