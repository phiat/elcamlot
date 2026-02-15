defmodule Elcamlot.Vehicles.SearchQuery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "search_queries" do
    field :query, :string
    field :filters, :map
    field :result_count, :integer
    field :searched_at, :utc_datetime
  end

  def changeset(search_query, attrs) do
    search_query
    |> cast(attrs, [:query, :filters, :result_count, :searched_at])
    |> validate_required([:query])
  end
end
