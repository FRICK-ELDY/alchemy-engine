defmodule Auth.Accounts.UserEmail do
  @moduledoc """
  Swoosh email templates for account lifecycle notifications.
  """

  import Swoosh.Email

  alias Auth.Accounts.User

  @spec verification_email(User.t(), String.t()) :: Swoosh.Email.t()
  def verification_email(%User{} = user, token) do
    url = verification_url(token)

    new()
    |> from(mail_from())
    |> to(to_string(user.email))
    |> subject("Verify your Alchemy account")
    |> text_body("""
    Hi #{to_string(user.username)},

    Please verify your email address by visiting the link below:

    #{url}

    This link expires in #{verification_ttl_hours()} hours.

    If you did not create an account, you can ignore this email.
    """)
  end

  @spec password_reset_email(User.t(), String.t()) :: Swoosh.Email.t()
  def password_reset_email(%User{} = user, token) do
    url = password_reset_url(token)

    new()
    |> from(mail_from())
    |> to(to_string(user.email))
    |> subject("Reset your Alchemy password")
    |> text_body("""
    Hi #{to_string(user.username)},

    We received a request to reset your password. Visit the link below to choose a new password:

    #{url}

    This link expires in #{password_reset_ttl_hours()} hour(s).

    If you did not request a password reset, you can ignore this email.
    """)
  end

  defp mail_from do
    Application.fetch_env!(:auth, :mail_from)
  end

  defp verification_url(token) do
    frontend_base_url() <> "/verify-email?token=" <> token
  end

  defp password_reset_url(token) do
    frontend_base_url() <> "/reset-password?token=" <> token
  end

  defp frontend_base_url do
    Application.fetch_env!(:auth, :auth_frontend_url)
    |> String.trim_trailing("/")
  end

  defp verification_ttl_hours do
    Application.fetch_env!(:auth, :email_verification_token_ttl_hours)
  end

  defp password_reset_ttl_hours do
    Application.fetch_env!(:auth, :password_reset_token_ttl_hours)
  end
end
