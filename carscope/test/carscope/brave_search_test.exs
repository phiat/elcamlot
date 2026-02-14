defmodule Carscope.BraveSearchTest do
  use ExUnit.Case, async: true

  alias Carscope.BraveSearch

  describe "parse_car_results/1" do
    test "extracts prices from search results" do
      mock_response = %{
        "web" => %{
          "results" => [
            %{
              "title" => "2021 Toyota Camry - $25,000",
              "description" => "Great condition, 45,000 miles",
              "url" => "https://www.carvana.com/vehicle/12345"
            },
            %{
              "title" => "Used Cars for Sale",
              "description" => "No price listed here",
              "url" => "https://www.example.com"
            },
            %{
              "title" => "2021 Camry SE - $23,500",
              "description" => "Clean title, 30k mi",
              "url" => "https://www.autotrader.com/listing/456"
            }
          ]
        }
      }

      results = BraveSearch.parse_car_results(mock_response)

      # Should only return results with prices
      assert length(results) == 2

      first = hd(results)
      assert first.price_cents == 25_000_00
      assert first.source == "carvana"
      assert first.mileage == 45_000
    end

    test "handles empty results" do
      assert BraveSearch.parse_car_results(%{}) == []
      assert BraveSearch.parse_car_results(%{"web" => %{}}) == []
    end

    test "returns error when API key missing" do
      original = Application.get_env(:carscope, :brave_search_api_key)
      Application.put_env(:carscope, :brave_search_api_key, nil)

      assert {:error, :missing_api_key} = BraveSearch.search("test")

      Application.put_env(:carscope, :brave_search_api_key, original)
    end
  end
end
