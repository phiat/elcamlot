defmodule ElcamlotWeb.ShareController do
  use ElcamlotWeb, :controller

  @token_max_age 7 * 24 * 60 * 60  # 7 days in seconds

  @doc """
  Verifies a share token and redirects to the shared LiveView.

  The token encodes {:share, vehicle_id} and is valid for 7 days.
  """
  def show(conn, %{"token" => token}) do
    case Phoenix.Token.verify(ElcamlotWeb.Endpoint, "share", token, max_age: @token_max_age) do
      {:ok, {:share, vehicle_id}} ->
        redirect(conn, to: ~p"/shared/#{vehicle_id}?token=#{token}")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "This share link has expired.")
        |> redirect(to: ~p"/users/log-in")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid share link.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  @doc "Generates a share token for a vehicle. Called from LiveViews."
  def generate_token(vehicle_id) do
    Phoenix.Token.sign(ElcamlotWeb.Endpoint, "share", {:share, vehicle_id})
  end
end
