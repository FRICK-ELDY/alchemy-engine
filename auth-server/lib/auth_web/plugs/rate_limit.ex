defmodule AuthWeb.Plugs.RateLimit do
  @moduledoc """
  Applies per-endpoint rate limits to auth API routes.

  - `login`: IP and identifier
  - `register`: IP and email
  - `refresh`: IP first, then refresh token family (falls back to token hash when unknown)
  - `resend_verification`: IP and email
  - `forgot_password`: IP and email
  - `reset_password`: IP
  - `verify_email`: IP
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Auth.Accounts.RefreshToken
  alias Auth.RateLimit

  def init(opts), do: opts

  def call(conn, _opts) do
    case action_for(conn) do
      nil -> conn
      action -> enforce(conn, action)
    end
  end

  defp enforce(conn, action) do
    limits = limits_for(action)

    case first_exceeded_axis(conn, action, limits) do
      nil ->
        conn

      {_axis, period_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds(period_ms)))
        |> put_status(:too_many_requests)
        |> put_view(AuthWeb.ErrorJSON)
        |> render(:"429")
        |> halt()
    end
  end

  defp first_exceeded_axis(conn, :refresh, limits) do
    ip = AuthWeb.ClientIp.from_conn(conn)

    case check_rate_limit(:refresh, :ip, ip, limits) do
      {:rate_limited, period_ms} ->
        {:ip, period_ms}

      :ok ->
        check_refresh_token_limit(conn, limits)
    end
  end

  defp first_exceeded_axis(conn, action, limits) do
    Enum.find_value(rate_limit_keys(conn, action), fn {axis, key} ->
      case check_rate_limit(action, axis, key, limits) do
        {:rate_limited, period_ms} -> {axis, period_ms}
        :ok -> false
      end
    end)
  end

  defp check_refresh_token_limit(conn, limits) do
    case conn.params["refresh_token"] do
      refresh_token when is_binary(refresh_token) and refresh_token != "" ->
        case check_rate_limit(:refresh, :token, token_key(refresh_token), limits) do
          {:rate_limited, period_ms} -> {:token, period_ms}
          :ok -> nil
        end

      _ ->
        nil
    end
  end

  defp check_rate_limit(action, axis, key, limits) do
    limit_config = Map.fetch!(limits, axis)

    case RateLimit.hit(bucket(action, axis), key, limit_config) do
      :ok -> :ok
      {:error, :rate_limited} -> {:rate_limited, limit_config.period_ms}
    end
  end

  defp action_for(%{path_info: ["api", "v1", "auth", "login"]}), do: :login
  defp action_for(%{path_info: ["api", "v1", "auth", "register"]}), do: :register
  defp action_for(%{path_info: ["api", "v1", "auth", "refresh"]}), do: :refresh

  defp action_for(%{path_info: ["api", "v1", "auth", "verify-email"]}),
    do: :verify_email

  defp action_for(%{path_info: ["api", "v1", "auth", "resend-verification"]}),
    do: :resend_verification

  defp action_for(%{path_info: ["api", "v1", "auth", "forgot-password"]}),
    do: :forgot_password

  defp action_for(%{path_info: ["api", "v1", "auth", "reset-password"]}),
    do: :reset_password

  defp action_for(_conn), do: nil

  defp rate_limit_keys(conn, :login) do
    with_ip(conn, fn ip ->
      case conn.params["identifier"] do
        identifier when is_binary(identifier) and identifier != "" ->
          [{:ip, ip}, {:identifier, normalize(identifier)}]

        _ ->
          [{:ip, ip}]
      end
    end)
  end

  defp rate_limit_keys(conn, :register) do
    with_ip(conn, fn ip ->
      case conn.params["email"] do
        email when is_binary(email) and email != "" ->
          [{:ip, ip}, {:email, normalize(email)}]

        _ ->
          [{:ip, ip}]
      end
    end)
  end

  defp rate_limit_keys(conn, :refresh) do
    with_ip(conn, fn ip -> [{:ip, ip}] end)
  end

  defp rate_limit_keys(conn, :resend_verification) do
    with_ip(conn, fn ip ->
      case conn.params["email"] do
        email when is_binary(email) and email != "" ->
          [{:ip, ip}, {:email, normalize(email)}]

        _ ->
          [{:ip, ip}]
      end
    end)
  end

  defp rate_limit_keys(conn, :forgot_password) do
    with_ip(conn, fn ip ->
      case conn.params["email"] do
        email when is_binary(email) and email != "" ->
          [{:ip, ip}, {:email, normalize(email)}]

        _ ->
          [{:ip, ip}]
      end
    end)
  end

  defp rate_limit_keys(conn, :reset_password) do
    with_ip(conn, fn ip -> [{:ip, ip}] end)
  end

  defp rate_limit_keys(conn, :verify_email) do
    with_ip(conn, fn ip -> [{:ip, ip}] end)
  end

  defp with_ip(conn, fun) do
    fun.(AuthWeb.ClientIp.from_conn(conn))
  end

  defp normalize(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp token_key(refresh_token) do
    hash =
      :crypto.hash(:sha256, refresh_token)
      |> Base.encode16(case: :lower)

    case RefreshToken.get_by_token_hash(hash) do
      {:ok, %{family_id: family_id}} -> "family:" <> family_id
      _ -> "token:" <> hash
    end
  end

  defp bucket(:login, :ip), do: :login_ip
  defp bucket(:login, :identifier), do: :login_identifier
  defp bucket(:register, :ip), do: :register_ip
  defp bucket(:register, :email), do: :register_email
  defp bucket(:refresh, :ip), do: :refresh_ip
  defp bucket(:refresh, :token), do: :refresh_token
  defp bucket(:resend_verification, :ip), do: :resend_verification_ip
  defp bucket(:resend_verification, :email), do: :resend_verification_email
  defp bucket(:forgot_password, :ip), do: :forgot_password_ip
  defp bucket(:forgot_password, :email), do: :forgot_password_email
  defp bucket(:reset_password, :ip), do: :reset_password_ip
  defp bucket(:verify_email, :ip), do: :verify_email_ip

  defp limits_for(action) do
    Application.get_env(:auth, RateLimit, [])
    |> Keyword.get(:limits, %{})
    |> Map.fetch!(action)
  end

  defp retry_after_seconds(period_ms) do
    now = System.system_time(:millisecond)
    remaining_ms = period_ms - rem(now, period_ms)

    remaining_ms
    |> div(1000)
    |> max(1)
  end
end
