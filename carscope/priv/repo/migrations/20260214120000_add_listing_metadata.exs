defmodule Carscope.Repo.Migrations.AddListingMetadata do
  use Ecto.Migration

  def change do
    alter table(:vehicles) do
      add :body_style, :string
    end

    alter table(:price_snapshots) do
      add :condition, :string
      add :listed_at, :utc_datetime
    end

    create_if_not_exists(index(:vehicles, [:body_style]))
    create_if_not_exists(index(:price_snapshots, [:condition]))
    create_if_not_exists(index(:price_snapshots, [:listed_at]))
  end
end
