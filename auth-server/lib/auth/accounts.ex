defmodule Auth.Accounts do
  @moduledoc """
  Authentication operations: register, login, refresh, logout.
  """

  alias Auth.Accounts.{AccountToken, RefreshToken, TokenRevocation, User, UserNotifier}
  alias Auth.{Password, Repo, Token}

  require Ash.Query
  require Logger
  import Ash.Expr

  @invalid_credentials_message "Invalid username/email or password"
  @generic_register_failure "could not create account"
  @verification_sent_message "If an account exists for that email, a verification message has been sent"
  @password_reset_sent_message "If an account exists for that email, password reset instructions have been sent"

  @typedoc """
  Session payload returned to clients after register/login/refresh.
  `:refresh_token` is only present when Remember Me is enabled.
  """
  @type session :: %{
          required(:access_token) => String.t(),
          required(:token_type) => String.t(),
          required(:expires_in) => non_neg_integer(),
          required(:user) => map(),
          optional(:refresh_token) => String.t()
        }

  @spec register(map()) :: {:ok, User.t()} | {:error, Ash.Error.t()} | {:error, :register_failed}
  def register(attrs) when is_map(attrs) do
    case User.register(attrs) do
      {:ok, user} = ok ->
        _ = deliver_verification_email(user)
        ok

      {:error, %Ash.Error.Invalid{} = error} ->
        if uniqueness_conflict?(error) do
          {:error, :register_failed}
        else
          {:error, error}
        end

      other ->
        other
    end
  end

  @doc """
  Logs in with a username or email. Identifiers containing `@` are treated
  as emails, otherwise as usernames (usernames cannot contain `@`).
  """
  @spec login(String.t(), String.t(), boolean()) ::
          {:ok, session()} | {:error, :invalid_credentials} | {:error, Ash.Error.t()}
  def login(identifier, password, remember_me? \\ false)
      when is_binary(identifier) and is_binary(password) do
    case get_by_identifier(identifier) do
      {:ok, user} ->
        pw_verified = Password.verify(password, user.password_hash)

        if pw_verified and user.status == :active do
          case issue_session(user, remember_me?) do
            {:ok, session} -> {:ok, session}
            _ -> {:error, :invalid_credentials}
          end
        else
          {:error, :invalid_credentials}
        end

      {:error, error} ->
        if Auth.AshErrors.not_found?(error) do
          Password.no_user_verify()
          {:error, :invalid_credentials}
        else
          {:error, error}
        end
    end
  end

  @doc """
  Issues an access token (and a refresh token when Remember Me is enabled)
  for an already-authenticated user.
  """
  @spec issue_session(User.t(), boolean()) :: {:ok, session()} | {:error, any()}
  def issue_session(%User{} = user, remember_me?) do
    with {:ok, access_token, _jti, expires_in} <- Token.generate(user) do
      session = %{
        access_token: access_token,
        token_type: "Bearer",
        expires_in: expires_in,
        user: user_payload(user)
      }

      if remember_me? do
        with {:ok, refresh_token} <- create_refresh_token(user) do
          {:ok, Map.put(session, :refresh_token, refresh_token)}
        end
      else
        {:ok, session}
      end
    end
  end

  @doc """
  Exchanges a refresh token for a new access token and a rotated refresh token.

  Each successful refresh revokes the presented token and issues a new one in the
  same token family. Reuse of a revoked token after the reuse grace period
  revokes the entire family.

  Tokens expire after `refresh_token_inactivity_days` of inactivity (sliding
  window on `last_used_at`).
  """
  @spec refresh(String.t()) :: {:ok, session()} | {:error, :invalid_refresh_token}
  def refresh(refresh_token) when is_binary(refresh_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_refresh_token_record(refresh_token) do
      {:ok, %{revoked_at: revoked_at} = record} when not is_nil(revoked_at) ->
        grace_seconds = Application.fetch_env!(:auth, :refresh_token_reuse_grace_seconds)

        if DateTime.diff(now, revoked_at, :second) > grace_seconds do
          revoke_refresh_token_family(record.family_id, now)
        end

        {:error, :invalid_refresh_token}

      {:ok, record} ->
        do_refresh(record, now)

      _ ->
        {:error, :invalid_refresh_token}
    end
  end

  @doc """
  Revokes the current access token, and the given refresh token when provided
  (only if it belongs to the same user).
  """
  @spec logout(String.t(), String.t(), DateTime.t(), String.t() | nil) ::
          {:ok, TokenRevocation.t()} | {:error, Ash.Error.t()}
  def logout(jti, user_id, expires_at, refresh_token \\ nil) do
    if is_binary(refresh_token), do: revoke_refresh_token(refresh_token, user_id)

    TokenRevocation.revoke(%{
      jti: jti,
      user_id: user_id,
      expires_at: expires_at
    })
  end

  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id) do
    Ash.get!(User, id)
  end

  @spec verify_email(String.t()) :: :ok | {:error, :invalid_token}
  def verify_email(token) when is_binary(token) do
    now = utc_now()

    case Repo.transaction(fn ->
           with {:ok, record} <- fetch_account_token(token, :email_verification),
                :ok <- ensure_account_token_usable(record, now),
                {:ok, user} <- fetch_user(record.user_id),
                :ok <- ensure_user_verifiable(user),
                {:ok, _} <- consume_account_token(record, now),
                {:ok, _} <- User.verify_email(user) do
             :ok
           else
             _ -> Repo.rollback(:invalid_token)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, :invalid_token} -> {:error, :invalid_token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  @spec resend_verification_email(String.t()) :: :ok
  def resend_verification_email(email) when is_binary(email) do
    case User.get_by_email(email) do
      {:ok, %User{status: :active, email_verified_at: nil} = user} ->
        _ = deliver_verification_email(user)
        :ok

      _ ->
        :ok
    end
  end

  @spec request_password_reset(String.t()) :: :ok
  def request_password_reset(email) when is_binary(email) do
    case User.get_by_email(email) do
      {:ok, %User{status: :active} = user} ->
        _ = deliver_password_reset_email(user)
        :ok

      _ ->
        :ok
    end
  end

  @spec reset_password(String.t(), String.t()) ::
          :ok | {:error, :invalid_token} | {:error, Ash.Error.t()}
  def reset_password(token, password) when is_binary(token) and is_binary(password) do
    now = utc_now()

    case Repo.transaction(fn ->
           with {:ok, record} <- fetch_account_token(token, :password_reset),
                :ok <- ensure_account_token_usable(record, now),
                {:ok, user} <- fetch_user(record.user_id),
                :ok <- ensure_user_active(user),
                {:ok, _} <- User.change_password(user, %{password: password}),
                {:ok, _} <- consume_account_token(record, now),
                :ok <- revoke_all_refresh_tokens(user.id, now) do
             :ok
           else
             {:error, %Ash.Error.Invalid{} = error} -> Repo.rollback(error)
             _ -> Repo.rollback(:invalid_token)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, %Ash.Error.Invalid{} = error} -> {:error, error}
      {:error, :invalid_token} -> {:error, :invalid_token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  @spec change_password(User.t(), String.t(), String.t()) ::
          :ok | {:error, :invalid_credentials} | {:error, Ash.Error.t()}
  def change_password(%User{} = user, current_password, new_password)
      when is_binary(current_password) and is_binary(new_password) do
    cond do
      user.status != :active ->
        {:error, :invalid_credentials}

      not Password.verify(current_password, user.password_hash) ->
        {:error, :invalid_credentials}

      true ->
        case Repo.transaction(fn ->
               case User.change_password(user, %{password: new_password}) do
                 {:ok, _} ->
                   revoke_all_refresh_tokens(user.id, utc_now())
                   :ok

                 {:error, error} ->
                   Repo.rollback(error)
               end
             end) do
          {:ok, :ok} -> :ok
          {:error, error} -> {:error, error}
        end
    end
  end

  @spec deactivate_account(User.t(), String.t(), DateTime.t(), String.t() | nil) ::
          :ok | {:error, Ash.Error.t()}
  def deactivate_account(%User{} = user, jti, expires_at, refresh_token \\ nil) do
    now = utc_now()

    case Repo.transaction(fn ->
           with {:ok, _} <- User.deactivate(user),
                :ok <- revoke_all_refresh_tokens(user.id, now),
                {:ok, _} <- logout(jti, user.id, expires_at, refresh_token) do
             :ok
           else
             {:error, error} -> Repo.rollback(error)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @spec generic_register_failure() :: String.t()
  def generic_register_failure, do: @generic_register_failure

  @spec verification_sent_message() :: String.t()
  def verification_sent_message, do: @verification_sent_message

  @spec password_reset_sent_message() :: String.t()
  def password_reset_sent_message, do: @password_reset_sent_message

  @doc false
  @spec create_account_token_for_test(User.t(), :email_verification | :password_reset, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def create_account_token_for_test(%User{} = user, purpose, opts \\ [])
      when purpose in [:email_verification, :password_reset] do
    expires_at = Keyword.get(opts, :expires_at)
    create_account_token(user, purpose, expires_at)
  end

  @spec invalid_credentials_message() :: String.t()
  def invalid_credentials_message, do: @invalid_credentials_message

  @spec user_payload(User.t()) :: map()
  def user_payload(%User{} = user) do
    %{
      user_id: user.id,
      username: to_string(user.username),
      email: to_string(user.email),
      email_verified: not is_nil(user.email_verified_at)
    }
  end

  defp do_refresh(record, now) do
    case Repo.transaction(fn ->
           with :ok <- ensure_refresh_token_usable(record, now),
                {:ok, %User{status: :active} = user} <- fetch_user(record.user_id),
                {:ok, new_refresh_token} <- rotate_refresh_token(record, user, now),
                {:ok, access_token, _jti, expires_in} <- Token.generate(user) do
             %{
               access_token: access_token,
               token_type: "Bearer",
               expires_in: expires_in,
               refresh_token: new_refresh_token,
               user: user_payload(user)
             }
           else
             _ -> Repo.rollback(:invalid_refresh_token)
           end
         end) do
      {:ok, session} -> {:ok, session}
      {:error, :invalid_refresh_token} -> {:error, :invalid_refresh_token}
      {:error, _} -> {:error, :invalid_refresh_token}
    end
  end

  defp get_by_identifier(identifier) do
    if String.contains?(identifier, "@") do
      User.get_by_email(identifier)
    else
      User.get_by_username(identifier)
    end
  end

  defp create_refresh_token(user, family_id \\ nil) do
    plaintext = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    family_id = family_id || Ecto.UUID.generate()

    case RefreshToken.create(%{
           user_id: user.id,
           family_id: family_id,
           token_hash: hash_refresh_token(plaintext),
           last_used_at: now
         }) do
      {:ok, _record} -> {:ok, plaintext}
      {:error, error} -> {:error, error}
    end
  end

  defp rotate_refresh_token(record, user, now) do
    with {:ok, _} <- RefreshToken.revoke(record, %{revoked_at: now}) do
      create_refresh_token(user, record.family_id)
    end
  end

  defp get_refresh_token_record(plaintext) do
    RefreshToken.get_by_token_hash(hash_refresh_token(plaintext))
  end

  defp ensure_refresh_token_usable(record, now) do
    inactivity_days = Application.fetch_env!(:auth, :refresh_token_inactivity_days)
    deadline = DateTime.add(record.last_used_at, inactivity_days * 86_400, :second)

    cond do
      not is_nil(record.revoked_at) -> {:error, :revoked}
      DateTime.compare(now, deadline) == :gt -> {:error, :expired}
      true -> :ok
    end
  end

  defp fetch_user(user_id) do
    Ash.get(User, user_id)
  end

  defp revoke_refresh_token_family(family_id, now) do
    RefreshToken
    |> Ash.Query.filter(expr(family_id == ^family_id and is_nil(revoked_at)))
    |> Ash.bulk_update(:revoke, %{revoked_at: now})

    :ok
  end

  defp revoke_refresh_token(plaintext, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_refresh_token_record(plaintext) do
      {:ok, %{user_id: ^user_id, revoked_at: nil} = record} ->
        RefreshToken.revoke(record, %{revoked_at: now})

      _ ->
        :noop
    end
  end

  defp hash_refresh_token(plaintext) do
    :sha256
    |> :crypto.hash(plaintext)
    |> Base.encode16(case: :lower)
  end

  defp deliver_verification_email(%User{email_verified_at: nil} = user) do
    case create_account_token(user, :email_verification) do
      {:ok, token} ->
        UserNotifier.deliver_verification_email(user, token)

      {:error, reason} ->
        Logger.error("failed to create email verification token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp deliver_verification_email(_user), do: :ok

  defp deliver_password_reset_email(%User{} = user) do
    case create_account_token(user, :password_reset) do
      {:ok, token} ->
        UserNotifier.deliver_password_reset_email(user, token)

      {:error, reason} ->
        Logger.error("failed to create password reset token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_account_token(%User{} = user, purpose, expires_at \\ nil) do
    invalidate_pending_account_tokens(user.id, purpose)

    plaintext = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    now = utc_now()
    expires_at = expires_at || account_token_expires_at(purpose, now)

    case AccountToken.create(%{
           user_id: user.id,
           token_hash: hash_account_token(plaintext),
           purpose: purpose,
           expires_at: expires_at
         }) do
      {:ok, _record} -> {:ok, plaintext}
      {:error, error} -> {:error, error}
    end
  end

  defp invalidate_pending_account_tokens(user_id, purpose) do
    now = utc_now()

    AccountToken
    |> Ash.Query.filter(
      expr(user_id == ^user_id and purpose == ^purpose and is_nil(used_at) and expires_at > ^now)
    )
    |> Ash.bulk_update!(:consume, %{used_at: now})

    :ok
  end

  defp fetch_account_token(plaintext, purpose) do
    hash = hash_account_token(plaintext)

    case AccountToken
         |> Ash.Query.for_read(:get_by_token_hash, %{token_hash: hash, purpose: purpose})
         |> Ash.Query.lock("FOR UPDATE")
         |> Ash.read_one() do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, record} ->
        {:ok, record}

      {:error, error} ->
        if Auth.AshErrors.not_found?(error), do: {:error, :not_found}, else: {:error, error}
    end
  end

  defp ensure_account_token_usable(record, now) do
    cond do
      not is_nil(record.used_at) -> {:error, :used}
      DateTime.compare(now, record.expires_at) != :lt -> {:error, :expired}
      true -> :ok
    end
  end

  defp consume_account_token(record, now) do
    AccountToken.consume(record, %{used_at: now})
  end

  defp ensure_user_verifiable(%User{status: :active, email_verified_at: nil}), do: :ok
  defp ensure_user_verifiable(%User{status: :active}), do: {:error, :already_verified}
  defp ensure_user_verifiable(_user), do: {:error, :inactive}

  defp ensure_user_active(%User{status: :active}), do: :ok
  defp ensure_user_active(_user), do: {:error, :inactive}

  defp account_token_expires_at(:email_verification, now) do
    hours = Application.fetch_env!(:auth, :email_verification_token_ttl_hours)
    DateTime.add(now, hours * 3_600, :second)
  end

  defp account_token_expires_at(:password_reset, now) do
    hours = Application.fetch_env!(:auth, :password_reset_token_ttl_hours)
    DateTime.add(now, hours * 3_600, :second)
  end

  defp hash_account_token(plaintext) do
    hash_refresh_token(plaintext)
  end

  defp revoke_all_refresh_tokens(user_id, now) do
    RefreshToken
    |> Ash.Query.filter(expr(user_id == ^user_id and is_nil(revoked_at)))
    |> Ash.bulk_update!(:revoke, %{revoked_at: now})

    :ok
  end

  defp uniqueness_conflict?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &uniqueness_conflict_error?/1)
  end

  defp uniqueness_conflict?(_), do: false

  defp uniqueness_conflict_error?(%Ash.Error.Changes.InvalidAttribute{
         field: field,
         message: message
       })
       when field in [:email, :username] and is_binary(message) do
    String.contains?(String.downcase(message), "already been taken")
  end

  defp uniqueness_conflict_error?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &uniqueness_conflict_error?/1)
  end

  defp uniqueness_conflict_error?(_), do: false

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
