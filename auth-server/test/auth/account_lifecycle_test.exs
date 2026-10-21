defmodule Auth.AccountLifecycleTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures
  import Swoosh.TestAssertions

  alias Auth.Accounts
  alias Auth.Accounts.User

  describe "register/1" do
    test "sends a verification email and leaves email unverified" do
      attrs = valid_register_attrs(%{email: "lifecycle@example.com"})

      assert {:ok, user} = Accounts.register(attrs)
      assert is_nil(user.email_verified_at)

      assert_email_sent(fn email ->
        assert email.to == [{"", "lifecycle@example.com"}]
        assert email.subject == "Verify your Alchemy account"
      end)
    end

    test "returns generic failure for duplicate email" do
      user_fixture(%{email: "dup@example.com"})

      assert {:error, :register_failed} =
               Accounts.register(valid_register_attrs(%{email: "dup@example.com"}))
    end

    test "returns generic failure for duplicate username" do
      user_fixture(%{username: "Taken"})

      assert {:error, :register_failed} =
               Accounts.register(valid_register_attrs(%{username: "taken"}))
    end
  end

  describe "verify_email/1" do
    test "marks the user verified and consumes the token" do
      user = user_fixture_without_verification_email(%{email: "verify-me@example.com"})
      token = account_token_fixture(user, :email_verification)

      assert :ok = Accounts.verify_email(token)

      user = Ash.get!(User, user.id)
      assert user.email_verified_at

      assert {:error, :invalid_token} = Accounts.verify_email(token)
    end

    test "rejects expired tokens" do
      user = user_fixture()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      token =
        account_token_fixture(user, :email_verification, expires_at: past)

      assert {:error, :invalid_token} = Accounts.verify_email(token)
    end
  end

  describe "resend_verification_email/1" do
    test "is enumeration-safe for unknown emails" do
      assert :ok = Accounts.resend_verification_email("missing@example.com")
      refute_email_sent()
    end

    test "sends another verification email for unverified users" do
      user = user_fixture(%{email: "resend@example.com"})
      assert :ok = Accounts.resend_verification_email("resend@example.com")

      assert_email_sent(fn email ->
        assert email.to == [{"", to_string(user.email)}]
      end)
    end
  end

  describe "password reset" do
    test "request_password_reset/1 is enumeration-safe" do
      assert :ok = Accounts.request_password_reset("missing@example.com")
      refute_email_sent()
    end

    test "resets password and revokes refresh tokens" do
      user = user_fixture_without_verification_email(%{email: "reset-me@example.com"})
      {:ok, session} = Accounts.issue_session(user, true)
      token = account_token_fixture(user, :password_reset)

      assert :ok = Accounts.reset_password(token, "Newpassword1")

      assert {:error, :invalid_credentials} =
               Accounts.login("reset-me@example.com", default_password())

      assert {:ok, _} = Accounts.login("reset-me@example.com", "Newpassword1")
      assert {:error, :invalid_refresh_token} = Accounts.refresh(session.refresh_token)
    end

    test "rejects invalid reset tokens" do
      assert {:error, :invalid_token} = Accounts.reset_password("bogus", "Newpassword1")
    end
  end

  describe "change_password/3" do
    test "updates password and revokes refresh tokens" do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)

      assert :ok = Accounts.change_password(user, default_password(), "Newpassword1")
      assert {:error, :invalid_refresh_token} = Accounts.refresh(session.refresh_token)
      assert {:ok, _} = Accounts.login(to_string(user.email), "Newpassword1")
    end

    test "rejects invalid current password" do
      user = user_fixture()

      assert {:error, :invalid_credentials} =
               Accounts.change_password(user, "Wrong-password1", "Newpassword1")
    end
  end

  describe "deactivate_account/4" do
    test "marks user deleted and revokes refresh tokens" do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      expires_at = DateTime.utc_now() |> DateTime.add(900, :second)

      assert :ok =
               Accounts.deactivate_account(
                 user,
                 Ecto.UUID.generate(),
                 expires_at,
                 session.refresh_token
               )

      user = Ash.get!(User, user.id)
      assert user.status == :deleted
      assert {:error, :invalid_refresh_token} = Accounts.refresh(session.refresh_token)
    end
  end
end
