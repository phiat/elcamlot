defmodule Carscope.Watchlist.SavedSearch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_searches" do
    field :name, :string
    field :query, :string
    field :filters, :map, default: %{}
    field :schedule, :string, default: "daily"
    field :active, :boolean, default: true
    field :last_run_at, :utc_datetime
    field :last_result_count, :integer

    belongs_to :user, Carscope.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(saved_search, attrs) do
    saved_search
    |> cast(attrs, [:name, :query, :filters, :schedule, :active, :last_run_at, :last_result_count, :user_id])
    |> validate_required([:name, :query, :user_id])
    |> validate_inclusion(:schedule, ["hourly", "6hr", "daily", "manual"])
  end
end
