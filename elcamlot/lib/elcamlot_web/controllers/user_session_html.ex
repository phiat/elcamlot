defmodule ElcamlotWeb.UserSessionHTML do
  use ElcamlotWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:elcamlot, Elcamlot.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
