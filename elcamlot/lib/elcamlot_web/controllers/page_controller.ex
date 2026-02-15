defmodule ElcamlotWeb.PageController do
  use ElcamlotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
