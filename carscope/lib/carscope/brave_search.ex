defmodule Carscope.BraveSearch do
  @moduledoc """
  Brave Search API client for fetching car listings and prices.

  Uses the Brave Web Search API to find current car listings,
  parse pricing information, and return structured results.
  """
  require Logger

  @base_url "https://api.search.brave.com/res/v1/web/search"

  @doc """
  Search for car listings. Returns parsed results with prices.

  ## Examples

      BraveSearch.search_cars("2021 Toyota Camry", state: "CA")
      BraveSearch.search_cars("Honda Civic 2020 price")
  """
  def search_cars(query, opts \\ []) do
    search_query = build_car_query(query, opts)

    case search(search_query) do
      {:ok, results} ->
        parsed = parse_car_results(results)
        {:ok, parsed}

      error ->
        error
    end
  end

  @doc "Raw Brave Search API call."
  def search(query, opts \\ []) do
    api_key = api_key()

    unless api_key do
      {:error, :missing_api_key}
    else
      count = Keyword.get(opts, :count, 20)
      offset = Keyword.get(opts, :offset, 0)

      params = %{q: query, count: count, offset: offset}

      case Req.get(@base_url,
             params: params,
             headers: [
               {"Accept", "application/json"},
               {"Accept-Encoding", "gzip"},
               {"X-Subscription-Token", api_key}
             ]
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Brave Search API returned #{status}: #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Parse Brave Search results into car listing structs."
  def parse_car_results(%{"web" => %{"results" => results}}) do
    results
    |> Enum.map(&parse_single_result/1)
    |> Enum.filter(& &1.price_cents)
  end

  def parse_car_results(_), do: []

  # --- Private ---

  defp build_car_query(query, opts) do
    base = "#{query} price for sale"
    state = Keyword.get(opts, :state)
    if state, do: "#{base} #{state}", else: base
  end

  defp parse_single_result(result) do
    title = result["title"] || ""
    description = result["description"] || ""
    url = result["url"] || ""
    text = "#{title} #{description}"

    %{
      title: title,
      url: url,
      description: description,
      price_cents: extract_price(text),
      mileage: extract_mileage(text),
      source: extract_source(url)
    }
  end

  defp extract_price(text) do
    case Regex.run(~r/\$([0-9]{1,3}(?:,?[0-9]{3})*)\b/, text) do
      [_, price_str] ->
        price_str
        |> String.replace(",", "")
        |> String.to_integer()
        |> Kernel.*(100)

      nil ->
        nil
    end
  end

  defp extract_mileage(text) do
    case Regex.run(~r/([\d,]+)\s*(?:mi(?:les?)?|k\s*mi)/i, text) do
      [_, miles_str] ->
        miles_str |> String.replace(",", "") |> String.to_integer()

      nil ->
        nil
    end
  end

  defp extract_source(url) do
    case URI.parse(url) do
      %{host: host} when is_binary(host) ->
        host
        |> String.replace(~r/^www\./, "")
        |> String.split(".")
        |> List.first()

      _ ->
        "unknown"
    end
  end

  defp api_key do
    Application.get_env(:carscope, :brave_search_api_key)
  end
end
