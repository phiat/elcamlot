defmodule Carscope.Vehicles.PriceSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "price_snapshots" do
    field :time, :utc_datetime
    field :price_cents, :integer
    field :mileage, :integer
    field :source, :string
    field :location, :string
    field :url, :string
    field :condition, :string
    field :listed_at, :utc_datetime

    belongs_to :vehicle, Carscope.Vehicles.Vehicle
  end

  @valid_conditions ~w(New Used Certified\ Pre-Owned Unknown)

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:time, :vehicle_id, :price_cents, :mileage, :source, :location, :url, :condition, :listed_at])
    |> validate_required([:time, :vehicle_id, :price_cents])
    |> validate_number(:price_cents, greater_than: 0)
    |> validate_inclusion(:condition, @valid_conditions)
    |> foreign_key_constraint(:vehicle_id)
  end
end
