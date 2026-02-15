defmodule Carscope.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CarscopeWeb.Telemetry,
      Carscope.Repo,
      {DNSCluster, query: Application.get_env(:carscope, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Carscope.PubSub},
      # Job processing
      {Oban, Application.fetch_env!(:carscope, Oban)},
      # Background workers
      Carscope.BraveSearch.Throttler,
      Carscope.MarketStatsRefresher,
      # Start to serve requests, typically the last entry
      CarscopeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Carscope.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CarscopeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
