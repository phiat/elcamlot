defmodule Elcamlot.Vehicles.DealScore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deal_scores" do
    field :score, :float
    field :percentile_rank, :float
    field :market_avg_cents, :integer
    field :vehicle_price_cents, :integer
    field :computed_at, :utc_datetime

    belongs_to :vehicle, Elcamlot.Vehicles.Vehicle
  end

  def changeset(deal_score, attrs) do
    deal_score
    |> cast(attrs, [:vehicle_id, :score, :percentile_rank, :market_avg_cents, :vehicle_price_cents, :computed_at])
    |> validate_required([:vehicle_id, :score, :computed_at])
    |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:vehicle_id)
  end
end
