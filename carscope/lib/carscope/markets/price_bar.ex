defmodule Carscope.Markets.PriceBar do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "price_bars" do
    field :time, :utc_datetime
    field :open_cents, :integer
    field :high_cents, :integer
    field :low_cents, :integer
    field :close_cents, :integer
    field :volume, :integer, default: 0
    field :timeframe, :string, default: "1D"

    belongs_to :instrument, Carscope.Markets.Instrument
  end

  def changeset(bar, attrs) do
    bar
    |> cast(attrs, [:time, :instrument_id, :open_cents, :high_cents, :low_cents, :close_cents, :volume, :timeframe])
    |> validate_required([:time, :instrument_id, :open_cents, :high_cents, :low_cents, :close_cents])
    |> validate_inclusion(:timeframe, ["1Min", "5Min", "15Min", "1H", "1D", "1W", "1M"])
  end
end
