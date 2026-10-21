defmodule AuthWeb.Plugs.Authenticate do
  @moduledoc """
  Verifies Bearer JWT and assigns `current_user`, `current_user_id`, and `token_claims`.
  """

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  alias Auth.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, claims, user} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_user_id, user.id)
        |> assign(:token_claims, claims)

      {:error, failure} ->
        log_authentication_failure(failure)

        conn
        |> put_status(failure.status)
        |> put_view(AuthWeb.ErrorJSON)
        |> render(status_template(failure.status))
        |> halt()
    end
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp authenticate(conn) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, claims, user} <- Token.verify(token) do
      {:ok, claims, user}
    else
      {:error, reason} ->
        {:error, classify_failure(reason)}

      other ->
        {:error,
         failure(
           :unauthorized,
           :unexpected_authenticate_result,
           %{result: inspect(other)},
           :error
         )}
    end
  rescue
    error ->
      {:error,
       failure(
         :unauthorized,
         :authenticate_exception,
         %{exception: Exception.format(:error, error, __STACKTRACE__)},
         :error
       )}
  end

  defp classify_failure(:missing_token),
    do: failure(:unauthorized, :missing_token, %{reason: :missing_token})

  defp classify_failure(:invalid_token),
    do: failure(:unauthorized, :invalid_token, %{reason: :invalid_token})

  defp classify_failure(:revoked),
    do: failure(:unauthorized, :revoked_token, %{reason: :revoked})

  defp classify_failure(:unauthorized),
    do: failure(:unauthorized, :unauthorized, %{reason: :unauthorized})

  defp classify_failure(:forbidden),
    do: failure(:forbidden, :forbidden, %{reason: :forbidden})

  defp classify_failure({:token_validation_failed, reason}) do
    code = if expired_reason?(reason), do: :expired_token, else: :invalid_token
    failure(:unauthorized, code, %{reason: inspect(reason)})
  end

  defp classify_failure({:account_verification_failed, reason}),
    do: failure(:unauthorized, :account_verification_failed, %{reason: inspect(reason)}, :error)

  defp classify_failure({:revocation_check_failed, reason}),
    do: failure(:unauthorized, :revocation_check_failed, %{reason: inspect(reason)}, :error)

  defp classify_failure({:token_verify_exception, error, stacktrace}) do
    failure(
      :unauthorized,
      :token_verify_exception,
      %{exception: Exception.format(:error, error, stacktrace)},
      :error
    )
  end

  defp classify_failure({:unexpected_token_validation_result, result}),
    do:
      failure(
        :unauthorized,
        :unexpected_token_validation_result,
        %{result: inspect(result)},
        :error
      )

  defp classify_failure({:unexpected_claim_verification_result, result}),
    do:
      failure(
        :unauthorized,
        :unexpected_claim_verification_result,
        %{result: inspect(result)},
        :error
      )

  defp classify_failure(reason),
    do:
      failure(
        :unauthorized,
        :unexpected_authentication_failure,
        %{reason: inspect(reason)},
        :error
      )

  defp expired_reason?(:token_expired), do: true

  defp expired_reason?(reason) when is_list(reason) do
    Keyword.get(reason, :claim) in ["exp", :exp] or
      message_mentions_expiration?(Keyword.get(reason, :message))
  end

  defp expired_reason?(%{reason: inner_reason}), do: expired_reason?(inner_reason)
  defp expired_reason?(_reason), do: false

  defp message_mentions_expiration?(message) when is_binary(message) do
    String.contains?(String.downcase(message), "expir")
  end

  defp message_mentions_expiration?(_message), do: false

  defp status_template(:unauthorized), do: :"401"
  defp status_template(:forbidden), do: :"403"
  defp status_template(_status), do: :"500"

  defp failure(status, code, context, log_level \\ :warning) do
    %{status: status, code: code, context: context, log_level: log_level}
  end

  defp log_authentication_failure(failure) do
    message =
      inspect(%{
        event: "auth.authenticate.failure",
        status: failure.status,
        code: failure.code,
        context: failure.context
      })

    case failure.log_level do
      :error -> Logger.error(message)
      _ -> Logger.warning(message)
    end
  end
end
