defmodule Auth.AccountsTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures

  alias Auth.Accounts
  alias Auth.Accounts.RefreshToken
  alias Auth.Password

  describe "register/1" do
    test "creates a user with hashed password and TOS stamp" do
      attrs = valid_register_attrs(%{username: "frick", email: "user@example.com"})

      assert {:ok, user} = Accounts.register(attrs)
      assert to_string(user.username) == "frick"
      assert to_string(user.email) == "user@example.com"
      assert user.status == :active
      assert user.birthday == ~D[2000-01-31]
      assert %DateTime{} = user.tos_agreed_at
      assert user.tos_version == Application.fetch_env!(:auth, :tos_version)
      assert Password.verify(default_password(), user.password_hash)
    end

    test "stores promo code when given" do
      assert {:ok, user} = Accounts.register(valid_register_attrs(%{promo_code: "ABC123"}))
      assert user.promo_code == "ABC123"
    end

    test "rejects duplicate email" do
      assert {:ok, _} = Accounts.register(valid_register_attrs(%{email: "dup@example.com"}))

      assert {:error, :register_failed} =
               Accounts.register(valid_register_attrs(%{email: "dup@example.com"}))
    end

    test "rejects duplicate username case-insensitively" do
      assert {:ok, _} = Accounts.register(valid_register_attrs(%{username: "Taken"}))

      assert {:error, :register_failed} =
               Accounts.register(valid_register_attrs(%{username: "taken"}))
    end

    test "rejects invalid username format" do
      for username <- ["ab", "way_too_long_username_over_20", "bad name", "bad@name"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.register(valid_register_attrs(%{username: username})),
               "expected #{inspect(username)} to be rejected"
      end
    end

    test "rejects invalid email format" do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register(valid_register_attrs(%{email: "not-an-email"}))
    end

    test "enforces password complexity" do
      for password <- ["Short1", "password1", "PASSWORD1", "Passwords"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.register(valid_register_attrs(%{password: password})),
               "expected #{inspect(password)} to be rejected"
      end
    end

    test "requires TOS agreement" do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register(valid_register_attrs(%{tos_agreed: false}))
    end

    test "rejects birthday in the future" do
      future = Date.add(Date.utc_today(), 1)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register(valid_register_attrs(%{birthday: future}))
    end
  end

  describe "login/3" do
    setup do
      user = user_fixture(%{username: "login_user", email: "login@example.com"})
      %{user: user}
    end

    test "logs in with email" do
      ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)

      assert {:ok, session} = Accounts.login("login@example.com", default_password())
      assert %{access_token: token, token_type: "Bearer", expires_in: ^ttl} = session
      assert is_binary(token)
      assert session.user.username == "login_user"
      refute Map.has_key?(session, :refresh_token)
    end

    test "logs in with username" do
      assert {:ok, session} = Accounts.login("login_user", default_password())
      assert session.user.email == "login@example.com"
    end

    test "username lookup is case-insensitive" do
      assert {:ok, _} = Accounts.login("LOGIN_USER", default_password())
    end

    test "returns refresh token when remember_me is set" do
      assert {:ok, session} = Accounts.login("login_user", default_password(), true)
      assert is_binary(session.refresh_token)
    end

    test "rejects invalid password" do
      assert {:error, :invalid_credentials} = Accounts.login("login_user", "Wrong-password1")
    end

    test "rejects unknown identifiers" do
      assert {:error, :invalid_credentials} =
               Accounts.login("missing@example.com", default_password())

      assert {:error, :invalid_credentials} = Accounts.login("missing_user", default_password())
    end

    test "rejects suspended user", %{user: user} do
      {:ok, _} =
        user
        |> Ash.Changeset.for_update(:set_status, %{status: :suspended})
        |> Ash.update()

      assert {:error, :invalid_credentials} = Accounts.login("login_user", default_password())
    end
  end

  describe "refresh/1" do
    setup do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      %{user: user, refresh_token: session.refresh_token}
    end

    test "issues a new access token and rotates the refresh token", %{
      refresh_token: refresh_token,
      user: user
    } do
      assert {:ok, session} = Accounts.refresh(refresh_token)
      assert is_binary(session.access_token)
      assert is_binary(session.refresh_token)
      assert session.refresh_token != refresh_token
      assert session.user.user_id == user.id
    end

    test "rejects a rotated refresh token", %{refresh_token: refresh_token} do
      assert {:ok, _} = Accounts.refresh(refresh_token)
      assert {:error, :invalid_refresh_token} = Accounts.refresh(refresh_token)
    end

    test "does not revoke the token family on immediate reuse", %{refresh_token: refresh_token} do
      assert {:ok, %{refresh_token: current}} = Accounts.refresh(refresh_token)
      assert {:error, :invalid_refresh_token} = Accounts.refresh(refresh_token)
      assert {:ok, _} = Accounts.refresh(current)
    end

    test "revokes the token family when reuse happens after the grace period", %{
      refresh_token: refresh_token
    } do
      assert {:ok, %{refresh_token: current}} = Accounts.refresh(refresh_token)

      {:ok, record} = RefreshToken.get_by_token_hash(hash_token(refresh_token))

      outside_grace =
        DateTime.add(DateTime.utc_now(), -30, :second) |> DateTime.truncate(:second)

      {:ok, _} = RefreshToken.revoke(record, %{revoked_at: outside_grace})

      assert {:error, :invalid_refresh_token} = Accounts.refresh(refresh_token)
      assert {:error, :invalid_refresh_token} = Accounts.refresh(current)
    end

    test "slides the inactivity window on use", %{user: user} do
      stale = DateTime.add(DateTime.utc_now(), -6 * 86_400, :second) |> DateTime.truncate(:second)
      {:ok, stale_token} = create_refresh_token_for_user(user, stale)

      assert {:ok, session} = Accounts.refresh(stale_token)

      {:ok, record} = RefreshToken.get_by_token_hash(hash_token(session.refresh_token))
      assert DateTime.diff(DateTime.utc_now(), record.last_used_at) < 60
    end

    test "rejects a token unused for more than 7 days", %{user: user} do
      expired =
        DateTime.add(DateTime.utc_now(), -8 * 86_400, :second) |> DateTime.truncate(:second)

      {:ok, expired_token} = create_refresh_token_for_user(user, expired)

      assert {:error, :invalid_refresh_token} = Accounts.refresh(expired_token)
    end

    test "rejects a revoked token", %{refresh_token: refresh_token} do
      {:ok, record} = RefreshToken.get_by_token_hash(hash_token(refresh_token))
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _} = RefreshToken.revoke(record, %{revoked_at: now})

      assert {:error, :invalid_refresh_token} = Accounts.refresh(refresh_token)
    end

    test "rejects an unknown token" do
      assert {:error, :invalid_refresh_token} = Accounts.refresh("bogus-token")
    end

    test "rejects when the user is suspended", %{user: user, refresh_token: refresh_token} do
      {:ok, _} =
        user
        |> Ash.Changeset.for_update(:set_status, %{status: :suspended})
        |> Ash.update()

      assert {:error, :invalid_refresh_token} = Accounts.refresh(refresh_token)
    end
  end

  describe "logout/4" do
    test "revokes the refresh token belonging to the user" do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      expires_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

      assert {:ok, _} =
               Accounts.logout(Ecto.UUID.generate(), user.id, expires_at, session.refresh_token)

      assert {:error, :invalid_refresh_token} = Accounts.refresh(session.refresh_token)
    end

    test "does not revoke another user's refresh token" do
      user = user_fixture()
      other = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      expires_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

      assert {:ok, _} =
               Accounts.logout(Ecto.UUID.generate(), other.id, expires_at, session.refresh_token)

      assert {:ok, _} = Accounts.refresh(session.refresh_token)
    end
  end

  describe "verify/2" do
    test "returns false for nil hash without crashing" do
      refute Password.verify("Password1", nil)
    end
  end

  defp hash_token(plaintext) do
    :sha256 |> :crypto.hash(plaintext) |> Base.encode16(case: :lower)
  end

  defp create_refresh_token_for_user(user, last_used_at) do
    plaintext = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    assert {:ok, _record} =
             RefreshToken.create(%{
               user_id: user.id,
               family_id: Ecto.UUID.generate(),
               token_hash: hash_token(plaintext),
               last_used_at: last_used_at
             })

    {:ok, plaintext}
  end
end
