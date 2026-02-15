defmodule Elcamlot.Integration.ContainerLifecycleTest do
  @moduledoc """
  Integration tests that exercise the Incus container lifecycle —
  the "testcontainers" piece. Verifies we can programmatically
  manage Postgres containers from Elixir.
  """
  use ExUnit.Case, async: false

  alias Elcamlot.Containers

  @moduletag :integration
  @test_container "elcamlot-pg-integration-test"

  setup_all do
    # Clean up any leftover test container
    if Containers.container_exists?(@test_container) do
      Containers.destroy(@test_container)
    end

    on_exit(fn ->
      Containers.destroy(@test_container)
    end)

    :ok
  end

  describe "container lifecycle" do
    test "launch, inspect, and destroy a container" do
      # Launch
      assert {:ok, @test_container} = Containers.launch(@test_container)

      # Should exist and be running
      assert Containers.container_exists?(@test_container)
      assert Containers.state(@test_container) == "RUNNING"

      # Should have an IP
      assert {:ok, ip} = Containers.get_ip(@test_container)
      assert ip =~ ~r/^\d+\.\d+\.\d+\.\d+$/

      # Can exec commands
      assert {:ok, output} = Containers.exec(@test_container, "echo hello")
      assert output == "hello"

      # Stop
      assert :ok = Containers.stop(@test_container)
      assert Containers.state(@test_container) == "STOPPED"

      # Restart
      assert {:ok, _} = Containers.start(@test_container)
      assert Containers.state(@test_container) == "RUNNING"

      # Destroy
      assert :ok = Containers.destroy(@test_container)
      refute Containers.container_exists?(@test_container)
    end
  end

  describe "list_containers" do
    test "lists elcamlot containers" do
      containers = Containers.list_containers()
      assert is_list(containers)

      # The main pg container should be listed if running
      pg = Enum.find(containers, &(&1.name == "elcamlot-pg"))

      if pg do
        assert pg.state == "RUNNING"
        assert pg.ip =~ ~r/^\d+\.\d+\.\d+\.\d+$/
      end
    end
  end
end
