defmodule Carscope.Watchlist.PriceAlert do
  use Ecto.Schema
  import Ecto.Changeset

  schema "price_alerts" do
    field :target_price_cents, :integer
    field :alert_type, :string, default: "below"
    field :active, :boolean, default: true
    field :triggered_at, :utc_datetime
    field :notified, :boolean, default: false

    belongs_to :user, Carscope.Accounts.User
    belongs_to :vehicle, Carscope.Vehicles.Vehicle

    timestamps(type: :utc_datetime)
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:target_price_cents, :alert_type, :active, :triggered_at, :notified, :user_id, :vehicle_id])
    |> validate_required([:target_price_cents, :alert_type, :user_id, :vehicle_id])
    |> validate_inclusion(:alert_type, ["below", "above", "pct_drop"])
    |> validate_number(:target_price_cents, greater_than: 0)
  end
end
