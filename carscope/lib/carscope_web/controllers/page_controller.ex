defmodule CarscopeWeb.PageController do
  use CarscopeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
