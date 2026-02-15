defmodule ElcamlotWeb.ExportController do
  use ElcamlotWeb, :controller

  alias Elcamlot.{Vehicles, Markets}

  @doc "Export a vehicle's price snapshots as CSV."
  def vehicle_csv(conn, %{"id" => id}) do
    vehicle = Vehicles.get_vehicle!(id)
    snapshots = Vehicles.list_price_snapshots(vehicle.id)

    filename =
      "#{vehicle.year}_#{vehicle.make}_#{vehicle.model}_snapshots.csv"
      |> String.replace(~r/[^a-zA-Z0-9_.\-]/, "_")

    csv = build_vehicle_csv(vehicle, snapshots)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  @doc "Export an instrument's price bars as CSV."
  def instrument_csv(conn, %{"id" => id}) do
    instrument = Markets.get_instrument!(id)
    bars = Markets.list_bars(instrument.id, limit: 10_000)

    filename =
      "#{instrument.symbol}_price_bars.csv"
      |> String.replace(~r/[^a-zA-Z0-9_.\-]/, "_")

    csv = build_instrument_csv(instrument, bars)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  # --- Private helpers ---

  defp build_vehicle_csv(vehicle, snapshots) do
    header = "Vehicle,Year,Make,Model,Trim,Date,Price (cents),Mileage,Source,Location,URL,Condition\r\n"

    rows =
      Enum.map_join(snapshots, "\r\n", fn s ->
        [
          vehicle_label(vehicle),
          to_string(vehicle.year),
          escape_csv(vehicle.make),
          escape_csv(vehicle.model),
          escape_csv(vehicle.trim || ""),
          format_datetime(s.time),
          to_string(s.price_cents),
          if(s.mileage, do: to_string(s.mileage), else: ""),
          escape_csv(s.source || ""),
          escape_csv(s.location || ""),
          escape_csv(s.url || ""),
          escape_csv(s.condition || "")
        ]
        |> Enum.join(",")
      end)

    header <> rows <> "\r\n"
  end

  defp build_instrument_csv(instrument, bars) do
    header = "Symbol,Name,Asset Class,Date,Open (cents),High (cents),Low (cents),Close (cents),Volume,Timeframe\r\n"

    rows =
      Enum.map_join(bars, "\r\n", fn b ->
        [
          escape_csv(instrument.symbol),
          escape_csv(instrument.name || ""),
          escape_csv(instrument.asset_class || ""),
          format_datetime(b.time),
          to_string(b.open_cents),
          to_string(b.high_cents),
          to_string(b.low_cents),
          to_string(b.close_cents),
          to_string(b.volume || 0),
          escape_csv(b.timeframe)
        ]
        |> Enum.join(",")
      end)

    header <> rows <> "\r\n"
  end

  defp vehicle_label(v) do
    escape_csv("#{v.year} #{v.make} #{v.model}")
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end

  defp escape_csv(nil), do: ""
end
