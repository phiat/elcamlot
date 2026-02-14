defmodule Carscope.Repo do
  use Ecto.Repo,
    otp_app: :carscope,
    adapter: Ecto.Adapters.Postgres
end
