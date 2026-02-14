defmodule Carscope.ContainerCase do
  @moduledoc """
  Test case for integration tests that need Incus containers.

  This is the "testcontainers" piece — manages container lifecycle
  around test suites. Spins up a fresh Postgres container before
  the suite, tears it down after.

  ## Usage

      use Carscope.ContainerCase

      test "queries work against real Postgres" do
        # Container is already running, Repo is connected
        assert Carscope.Vehicles.list_vehicles() == []
      end
  """
  use ExUnit.CaseTemplate

  alias Carscope.Containers

  @test_container "carscope-pg-test"

  using do
    quote do
      alias Carscope.Repo
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
    original_config = Application.get_env(:carscope, Carscope.Repo)

    Application.put_env(:carscope, Carscope.Repo,
      Keyword.merge(original_config,
        hostname: ip,
        database: "carscope",
        username: "carscope",
        password: "carscope"
      )
    )

    on_exit(fn ->
      # Restore original config
      Application.put_env(:carscope, Carscope.Repo, original_config)

      # Tear down the test container
      Containers.destroy(@test_container)
    end)

    %{container: @test_container, pg_ip: ip}
  end
end
