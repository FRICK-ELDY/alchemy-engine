defmodule Auth.Accounts.UserNotifier do
  @moduledoc """
  Delivers account lifecycle emails through `Auth.Mailer`.
  """

  require Logger

  alias Auth.Accounts.{User, UserEmail}
  alias Auth.Mailer

  @spec deliver_verification_email(User.t(), String.t()) :: :ok | {:error, term()}
  def deliver_verification_email(%User{} = user, token) when is_binary(token) do
    deliver(UserEmail.verification_email(user, token))
  end

  @spec deliver_password_reset_email(User.t(), String.t()) :: :ok | {:error, term()}
  def deliver_password_reset_email(%User{} = user, token) when is_binary(token) do
    deliver(UserEmail.password_reset_email(user, token))
  end

  defp deliver(email) do
    case Mailer.deliver(email) do
      {:ok, _response} ->
        :ok

      {:error, reason} = error ->
        Logger.error("failed to deliver email: #{inspect(reason)}")
        error
    end
  end
end
