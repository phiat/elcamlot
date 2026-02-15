defmodule Elcamlot.Integration.PriceTrackingTest do
  @moduledoc """
  Integration test for the full price tracking pipeline:
  create vehicle → add price snapshots → query stats.

  Uses the existing Incus Postgres container.
  """
  use Elcamlot.DataCase, async: false

  alias Elcamlot.Vehicles

  @moduletag :integration

  describe "price tracking pipeline" do
    test "create vehicle, add snapshots, and query stats" do
      # Create a test vehicle
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          make: "TestMake",
          model: "TestModel",
          year: 2024,
          trim: "Integration"
        })

      assert vehicle.id

      # Add price snapshots
      prices = [25_000_00, 23_500_00, 27_000_00, 24_000_00, 26_500_00]

      for price <- prices do
        {:ok, _snap} =
          Vehicles.create_price_snapshot(%{
            time: DateTime.utc_now(),
            vehicle_id: vehicle.id,
            price_cents: price,
            source: "integration_test",
            location: "test"
          })
      end

      # Query stats
      stats = Vehicles.price_stats(vehicle.id)
      assert stats.count == 5
      assert stats.min_price == 23_500_00
      assert stats.max_price == 27_000_00
      assert stats.avg_price > 0

      # List snapshots
      snapshots = Vehicles.list_price_snapshots(vehicle.id)
      assert length(snapshots) == 5

      # Search
      results = Vehicles.search_vehicles("TestMake")
      assert length(results) >= 1
      assert hd(results).make == "TestMake"
    end

    test "find_or_create_vehicle is idempotent" do
      attrs = %{make: "Idempotent", model: "Test", year: 2025}

      {:ok, v1} = Vehicles.find_or_create_vehicle(attrs)
      {:ok, v2} = Vehicles.find_or_create_vehicle(attrs)

      assert v1.id == v2.id
    end

    test "log_search records query" do
      {:ok, query} = Vehicles.log_search("2024 Honda Civic", 15)
      assert query.query == "2024 Honda Civic"
      assert query.result_count == 15
    end
  end
end
