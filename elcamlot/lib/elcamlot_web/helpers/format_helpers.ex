defmodule ElcamlotWeb.Helpers.FormatHelpers do
  @moduledoc "Shared formatting utilities for LiveViews and templates."

  def format_price(nil), do: "—"
  def format_price(%Decimal{} = cents), do: format_price(Decimal.to_float(cents))

  def format_price(cents) when is_number(cents) do
    dollars = trunc(cents / 100)
    "$#{dollars |> Integer.to_string() |> format_number()}"
  end

  def format_number(num) when is_integer(num), do: format_number(Integer.to_string(num))

  def format_number(str) when is_binary(str) do
    str
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_date(nil), do: ""
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")
  def format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  def format_relative_time(nil), do: "—"

  def format_relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  def deal_badge_class("great deal"), do: "bg-success/20 text-success"
  def deal_badge_class("good deal"), do: "bg-success/10 text-success"
  def deal_badge_class("fair price"), do: "bg-info/10 text-info"
  def deal_badge_class("above market"), do: "bg-warning/10 text-warning"
  def deal_badge_class("overpriced"), do: "bg-error/10 text-error"
  def deal_badge_class(_), do: "bg-base-200 text-base-content/60"
end
