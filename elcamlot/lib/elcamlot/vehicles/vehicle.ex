defmodule Elcamlot.Vehicles.Vehicle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vehicles" do
    field :make, :string
    field :model, :string
    field :year, :integer
    field :trim, :string
    field :body_style, :string

    field :avg_price, :integer, virtual: true
    field :snapshot_count, :integer, virtual: true, default: 0
    field :latest_snapshot_at, :utc_datetime, virtual: true

    has_many :price_snapshots, Elcamlot.Vehicles.PriceSnapshot
    has_many :deal_scores, Elcamlot.Vehicles.DealScore

    timestamps(type: :utc_datetime, updated_at: false, inserted_at: :created_at)
  end

  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [:make, :model, :year, :trim, :body_style])
    |> validate_required([:make, :model, :year])
    |> validate_number(:year, greater_than: 1900, less_than: 2030)
    |> unique_constraint([:make, :model, :year, :trim])
  end
end
