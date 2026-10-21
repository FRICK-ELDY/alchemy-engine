defmodule Auth.Accounts.UserNotifierTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures
  import Swoosh.TestAssertions

  alias Auth.Accounts.{User, UserEmail, UserNotifier}

  test "deliver_verification_email/2 sends to the user address" do
    user = email_user("verify@example.com")

    assert :ok = UserNotifier.deliver_verification_email(user, "token-123")

    assert_email_sent(fn email ->
      assert email.to == [{"", "verify@example.com"}]
      assert email.subject == "Verify your Alchemy account"
      assert email.text_body =~ "token-123"
    end)
  end

  test "deliver_password_reset_email/2 includes reset link" do
    user = email_user("reset@example.com")

    assert :ok = UserNotifier.deliver_password_reset_email(user, "reset-token")

    assert_email_sent(fn email ->
      assert email.to == [{"", "reset@example.com"}]
      assert email.subject == "Reset your Alchemy password"
      assert email.text_body =~ "reset-token"
    end)
  end

  test "verification_email/2 builds frontend verification URL" do
    user = email_user("url@example.com")
    email = UserEmail.verification_email(user, "abc")

    assert email.text_body =~ "/verify-email?token=abc"
  end

  test "verification_email/2 trims trailing slash from frontend base URL" do
    previous = Application.get_env(:auth, :auth_frontend_url)
    Application.put_env(:auth, :auth_frontend_url, "http://localhost:4000/")

    on_exit(fn ->
      if previous do
        Application.put_env(:auth, :auth_frontend_url, previous)
      else
        Application.delete_env(:auth, :auth_frontend_url)
      end
    end)

    user = email_user("url@example.com")
    email = UserEmail.verification_email(user, "abc")

    assert email.text_body =~ "http://localhost:4000/verify-email?token=abc"
    refute email.text_body =~ "//verify-email"
  end

  defp email_user(email) do
    %User{
      id: Ecto.UUID.generate(),
      username: "mailuser",
      email: email
    }
  end
end
