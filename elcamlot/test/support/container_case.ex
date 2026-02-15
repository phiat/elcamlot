defmodule Elcamlot.ContainerCase do
  @moduledoc """
  Test case for integration tests that need Incus containers.

  This is the "testcontainers" piece — manages container lifecycle
  around test suites. Spins up a fresh Postgres container before
  the suite, tears it down after.

  ## Usage

      use Elcamlot.ContainerCase

      test "queries work against real Postgres" do
        # Container is already running, Repo is connected
        assert Elcamlot.Vehicles.list_vehicles() == []
      end
  """
  use ExUnit.CaseTemplate

  alias Elcamlot.Containers

  @test_container "elcamlot-pg-test"

  using do
    quote do
      alias Elcamlot.Repo
      import Ecto.Query
    end
  end

  setup_all do
    # Launch a fresh test Postgres container
    {:ok, %{ip: ip}} =
      Containers.setup_postgres(name: @test_container)

    # Wait for Postgres to be fully ready
    :ok = Containers.wait_for_pg(@test_container)

    # Reconfigure Repo to point at the test container
    # (tests using this case get their own Postgres instance)
    original_config = Application.get_env(:elcamlot, Elcamlot.Repo)

    Application.put_env(:elcamlot, Elcamlot.Repo,
      Keyword.merge(original_config,
        hostname: ip,
        database: "elcamlot",
        username: "elcamlot",
        password: "elcamlot"
      )
    )

    on_exit(fn ->
      # Restore original config
      Application.put_env(:elcamlot, Elcamlot.Repo, original_config)

      # Tear down the test container
      Containers.destroy(@test_container)
    end)

    %{container: @test_container, pg_ip: ip}
  end
end
