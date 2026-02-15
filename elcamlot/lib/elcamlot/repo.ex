defmodule Elcamlot.Repo do
  use Ecto.Repo,
    otp_app: :elcamlot,
    adapter: Ecto.Adapters.Postgres
end
