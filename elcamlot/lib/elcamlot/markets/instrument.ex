defmodule Elcamlot.Markets.Instrument do
  use Ecto.Schema
  import Ecto.Changeset

  schema "instruments" do
    field :symbol, :string
    field :name, :string
    field :asset_class, :string, default: "us_equity"
    field :exchange, :string
    field :status, :string, default: "active"

    has_many :price_bars, Elcamlot.Markets.PriceBar

    timestamps(type: :utc_datetime, updated_at: false, inserted_at: :created_at)
  end

  def changeset(instrument, attrs) do
    instrument
    |> cast(attrs, [:symbol, :name, :asset_class, :exchange, :status])
    |> validate_required([:symbol, :asset_class])
    |> validate_inclusion(:asset_class, ["us_equity", "crypto", "us_option"])
    |> unique_constraint(:symbol)
  end
end
