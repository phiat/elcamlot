defmodule CarscopeWeb.UserSessionHTML do
  use CarscopeWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:carscope, Carscope.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
