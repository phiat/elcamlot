import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :elcamlot, Elcamlot.Repo,
  username: "elcamlot",
  password: "elcamlot",
  hostname: System.get_env("ELCAMLOT_PG_HOST") || "localhost",
  database: "elcamlot_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :elcamlot, ElcamlotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CtArh4d3N8B5dbwcB5id5pLX0pHD/pD6DdJts0S1BqUQcrGJsrry5iK1q8JBfl1x",
  server: false

# Disable Oban in tests
config :elcamlot, Oban, testing: :inline

# Swoosh test adapter
config :elcamlot, Elcamlot.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
