defmodule AuthWeb.AuthController do
  use AuthWeb, :controller

  require Logger

  alias Auth.Accounts

  @register_required ~w(username email password birthday tos_agreed)

  def register(conn, params) do
    missing = Enum.filter(@register_required, &blank?(params[&1]))

    if missing == [] do
      do_register(conn, params)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        errors: %{
          detail: "#{Enum.join(missing, ", ")} required",
          fields: Map.new(missing, &{&1, ["is required"]})
        }
      })
    end
  end

  defp do_register(conn, params) do
    attrs = %{
      username: params["username"],
      email: params["email"],
      password: params["password"],
      birthday: params["birthday"],
      promo_code: presence(params["promo_code"]),
      tos_agreed: params["tos_agreed"]
    }

    with {:ok, user} <- Accounts.register(attrs),
         {:ok, session} <- Accounts.issue_session(user, params["remember_me"] == true) do
      conn
      |> put_status(:created)
      |> json(session)
    else
      {:error, :register_failed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: Accounts.generic_register_failure()}})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: register_errors(error)})

      {:error, other} ->
        Logger.error("registration failed unexpectedly: #{inspect(other)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{errors: %{detail: "An unexpected error occurred"}})
    end
  end

  def login(conn, %{"identifier" => identifier, "password" => password} = params)
      when is_binary(identifier) and is_binary(password) do
    case Accounts.login(identifier, password, params["remember_me"] == true) do
      {:ok, session} ->
        json(conn, session)

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: Accounts.invalid_credentials_message()}})

      {:error, other} ->
        Logger.error("login failed unexpectedly: #{inspect(other)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{errors: %{detail: "An unexpected error occurred"}})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: Accounts.invalid_credentials_message()}})
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) when is_binary(refresh_token) do
    case Accounts.refresh(refresh_token) do
      {:ok, session} ->
        json(conn, session)

      {:error, :invalid_refresh_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Invalid or expired refresh token"}})
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: "Invalid or expired refresh token"}})
  end

  def logout(conn, params) do
    claims = conn.assigns.token_claims
    expires_at = DateTime.from_unix!(claims["exp"])
    refresh_token = presence(params["refresh_token"])

    case Accounts.logout(claims["jti"], claims["sub"], expires_at, refresh_token) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, _error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: "could not revoke token"}})
    end
  end

  def me(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      user_id: user.id,
      username: to_string(user.username),
      email: to_string(user.email),
      status: to_string(user.status),
      email_verified: not is_nil(user.email_verified_at)
    })
  end

  def verify_email(conn, %{"token" => token}) when is_binary(token) do
    case Accounts.verify_email(token) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :invalid_token} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: "Invalid or expired verification token"}})
    end
  end

  def verify_email(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: "Invalid or expired verification token"}})
  end

  def resend_verification(conn, %{"email" => email}) when is_binary(email) do
    :ok = Accounts.resend_verification_email(email)

    json(conn, %{message: Accounts.verification_sent_message()})
  end

  def resend_verification(conn, _params) do
    json(conn, %{message: Accounts.verification_sent_message()})
  end

  def forgot_password(conn, %{"email" => email}) when is_binary(email) do
    :ok = Accounts.request_password_reset(email)

    json(conn, %{message: Accounts.password_reset_sent_message()})
  end

  def forgot_password(conn, _params) do
    json(conn, %{message: Accounts.password_reset_sent_message()})
  end

  def reset_password(conn, %{"token" => token, "password" => password})
      when is_binary(token) and is_binary(password) do
    case Accounts.reset_password(token, password) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :invalid_token} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: "Invalid or expired reset token"}})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: register_errors(error)})
    end
  end

  def reset_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: "Invalid or expired reset token"}})
  end

  def change_password(conn, %{"current_password" => current, "new_password" => new})
      when is_binary(current) and is_binary(new) do
    user = conn.assigns.current_user

    case Accounts.change_password(user, current, new) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: Accounts.invalid_credentials_message()}})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: register_errors(error)})
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: "current_password and new_password are required"}})
  end

  def deactivate(conn, params) do
    user = conn.assigns.current_user
    claims = conn.assigns.token_claims
    expires_at = DateTime.from_unix!(claims["exp"])
    refresh_token = presence(params["refresh_token"])

    case Accounts.deactivate_account(user, claims["jti"], expires_at, refresh_token) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, _error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: "could not deactivate account"}})
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp presence(value), do: if(blank?(value), do: nil, else: value)

  defp register_errors(%Ash.Error.Invalid{} = error) do
    fields = collect_field_errors(error.errors, %{})

    detail =
      if map_size(fields) == 0 do
        "could not create user"
      else
        "validation failed"
      end

    %{detail: detail, fields: fields}
  end

  defp collect_field_errors(errors, acc) when is_list(errors) do
    Enum.reduce(errors, acc, &collect_field_error/2)
  end

  defp collect_field_error(%Ash.Error.Changes.InvalidAttribute{field: field} = e, acc)
       when not is_nil(field) do
    put_field_error(acc, field, e.message)
  end

  defp collect_field_error(%Ash.Error.Changes.InvalidArgument{field: field} = e, acc)
       when not is_nil(field) do
    put_field_error(acc, field, e.message)
  end

  defp collect_field_error(%Ash.Error.Changes.Required{field: field}, acc)
       when not is_nil(field) do
    put_field_error(acc, field, "is required")
  end

  defp collect_field_error(%Ash.Error.Changes.InvalidChanges{fields: [field | _]} = e, acc)
       when not is_nil(field) do
    put_field_error(acc, field, e.message)
  end

  defp collect_field_error(error, acc) when is_struct(error) do
    case Map.get(error, :errors) do
      nested when is_list(nested) -> collect_field_errors(nested, acc)
      _ -> acc
    end
  end

  defp collect_field_error(_error, acc), do: acc

  defp put_field_error(acc, field, message) do
    message = message || "is invalid"
    Map.update(acc, to_string(field), [message], &(&1 ++ [message]))
  end
end
