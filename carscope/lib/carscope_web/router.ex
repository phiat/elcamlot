defmodule CarscopeWeb.Router do
  use CarscopeWeb, :router

  import CarscopeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CarscopeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug CarscopeWeb.Plugs.RateLimit
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", CarscopeWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in dev
  if Application.compile_env(:carscope, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", CarscopeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", CarscopeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/", SearchLive, :index
    live "/vehicle/:id", DashboardLive, :show
    live "/market", MarketLive, :index
    live "/finance", FinanceLive, :index
    live "/finance/:id", FinanceDashboardLive, :show

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", CarscopeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
