defmodule Auth.Token do
  @moduledoc """
  JWT access tokens (RS256) for alchemy-platform sessions.
  """

  alias Auth.Accounts.{TokenRevocation, User}
  alias Auth.Token.Keys

  @doc """
  Issues a signed access token for the given user.

  Returns `{:ok, token, jti, expires_in}`.
  """
  @spec generate(User.t()) :: {:ok, String.t(), String.t(), non_neg_integer()}
  def generate(%User{} = user) do
    jti = Ecto.UUID.generate()
    ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)

    extra_claims = %{
      "sub" => user.id,
      "status" => to_string(user.status),
      "jti" => jti
    }

    signer = Keys.signer()

    case Joken.generate_and_sign(token_config(), extra_claims, signer) do
      {:ok, token, _claims} -> {:ok, token, jti, ttl}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies a bearer token and returns claims when valid.
  """
  @spec verify(String.t()) :: {:ok, map(), User.t()} | {:error, any()}
  def verify(token) when is_binary(token) do
    with {:ok, %{"kid" => kid}} <- peek_kid(token),
         {:ok, signer} <- Keys.signer_for_kid(kid),
         {:ok, claims} <- Joken.verify_and_validate(token_config(), token, signer) do
      verify_claims(claims)
    else
      {:error, :unknown_kid} ->
        {:error, :unknown_kid}

      {:error, reason} ->
        {:error, {:token_validation_failed, reason}}

      other ->
        {:error, {:unexpected_token_validation_result, other}}
    end
  rescue
    error ->
      {:error, {:token_verify_exception, error, __STACKTRACE__}}
  end

  defp peek_kid(token) do
    case Joken.peek_header(token) do
      {:ok, %{"kid" => kid}} when is_binary(kid) and kid != "" ->
        {:ok, %{"kid" => kid}}

      {:ok, _header} ->
        {:error, :missing_kid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp token_config do
    ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)
    issuer = Application.fetch_env!(:auth, :jwt_issuer)
    audience = Application.fetch_env!(:auth, :jwt_audience)

    Joken.Config.default_claims(default_exp: ttl, iss: issuer, aud: audience)
    |> Joken.Config.add_claim("sub", fn -> nil end, &valid_uuid?/1)
    |> Joken.Config.add_claim("status", fn -> nil end, &valid_status?/1)
    |> Joken.Config.add_claim("jti", fn -> nil end, &valid_uuid?/1)
  end

  defp valid_uuid?(value) when is_binary(value) do
    match?({:ok, _}, Ecto.UUID.cast(value))
  end

  defp valid_uuid?(_), do: false

  defp valid_status?(value) when value in ["active", "suspended", "deleted"], do: true
  defp valid_status?(_), do: false

  defp ensure_not_revoked(jti) do
    case TokenRevocation.get_by_jti(jti) do
      {:ok, _} -> {:error, :revoked}
      {:error, error} -> if Auth.AshErrors.not_found?(error), do: :ok, else: {:error, error}
    end
  end

  defp ensure_user_active(user_id) do
    case Ash.get(User, user_id) do
      {:ok, %{status: :active} = user} ->
        {:ok, user}

      {:ok, %{status: :deleted}} ->
        {:error, :unauthorized}

      {:ok, _} ->
        {:error, :forbidden}

      {:error, error} ->
        if Auth.AshErrors.not_found?(error), do: {:error, :unauthorized}, else: {:error, error}
    end
  end

  defp verify_claims(claims) do
    with {:revocation, :ok} <- {:revocation, ensure_not_revoked(claims["jti"])},
         {:user, {:ok, user}} <- {:user, ensure_user_active(claims["sub"])} do
      {:ok, claims, user}
    else
      {:revocation, {:error, :revoked}} -> {:error, :revoked}
      {:revocation, {:error, error}} -> {:error, {:revocation_check_failed, error}}
      {:user, {:error, :unauthorized}} -> {:error, :unauthorized}
      {:user, {:error, :forbidden}} -> {:error, :forbidden}
      {:user, {:error, error}} -> {:error, {:account_verification_failed, error}}
      other -> {:error, {:unexpected_claim_verification_result, other}}
    end
  end
end
