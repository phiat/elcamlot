defmodule ElcamlotWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Hammer.
  Anonymous: 60 req/min, Authenticated: 300 req/min.
  """
  import Plug.Conn

  @anonymous_limit Application.compile_env(:elcamlot, :rate_limit_anonymous, 60)
  @authenticated_limit Application.compile_env(:elcamlot, :rate_limit_authenticated, 300)
  @window_ms Application.compile_env(:elcamlot, :rate_limit_window_ms, 60_000)

  def init(opts), do: opts

  def call(conn, _opts) do
    key = rate_limit_key(conn)
    limit = if conn.assigns[:current_scope], do: @authenticated_limit, else: @anonymous_limit

    case Hammer.check_rate("request:#{key}", @window_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, "Rate limit exceeded. Try again in 60 seconds.")
        |> halt()
    end
  end

  defp rate_limit_key(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
