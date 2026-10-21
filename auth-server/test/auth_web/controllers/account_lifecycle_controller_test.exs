defmodule AuthWeb.AccountLifecycleControllerTest do
  use AuthWeb.ConnCase, async: true

  import Auth.AccountsFixtures
  import Swoosh.TestAssertions

  alias Auth.Accounts

  describe "POST /api/v1/auth/verify-email" do
    test "verifies a user email", %{conn: conn} do
      user = user_fixture_without_verification_email(%{email: "verify-api@example.com"})
      token = account_token_fixture(user, :email_verification)

      conn = post(conn, ~p"/api/v1/auth/verify-email", %{"token" => token})
      assert response(conn, 204)

      user = Ash.get!(Auth.Accounts.User, user.id)
      assert user.email_verified_at
    end

    test "returns 422 for invalid token", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/verify-email", %{"token" => "invalid"})

      assert %{"errors" => %{"detail" => "Invalid or expired verification token"}} =
               json_response(conn, 422)
    end
  end

  describe "POST /api/v1/auth/resend-verification" do
    test "returns the same message for unknown emails", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/resend-verification", %{"email" => "missing@example.com"})

      assert %{"message" => message} = json_response(conn, 200)
      assert message == Accounts.verification_sent_message()
      refute_email_sent()
    end
  end

  describe "password reset API" do
    test "forgot-password is enumeration-safe", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/forgot-password", %{"email" => "missing@example.com"})

      assert %{"message" => message} = json_response(conn, 200)
      assert message == Accounts.password_reset_sent_message()
      refute_email_sent()
    end

    test "reset-password updates the password", %{conn: conn} do
      user = user_fixture_without_verification_email(%{email: "reset-api@example.com"})
      token = account_token_fixture(user, :password_reset)

      conn =
        post(conn, ~p"/api/v1/auth/reset-password", %{
          "token" => token,
          "password" => "Newpassword1"
        })

      assert response(conn, 204)
      assert {:ok, _} = Accounts.login("reset-api@example.com", "Newpassword1")
    end
  end

  describe "authenticated lifecycle routes" do
    setup %{conn: conn} do
      user = user_fixture(%{username: "lifecycle_user", email: "lifecycle@example.com"})

      conn =
        post(conn, ~p"/api/v1/auth/login", %{
          "identifier" => "lifecycle@example.com",
          "password" => default_password(),
          "remember_me" => true
        })

      body = json_response(conn, 200)
      access_token = body["access_token"]

      auth_conn = put_req_header(build_conn(), "authorization", "Bearer " <> access_token)

      %{
        auth_conn: auth_conn,
        refresh_token: body["refresh_token"],
        user: user
      }
    end

    test "POST /api/v1/auth/change-password", %{auth_conn: conn, refresh_token: refresh_token} do
      conn =
        post(conn, ~p"/api/v1/auth/change-password", %{
          "current_password" => default_password(),
          "new_password" => "Newpassword1"
        })

      assert response(conn, 204)

      refresh_conn =
        post(build_conn(), ~p"/api/v1/auth/refresh", %{"refresh_token" => refresh_token})

      assert json_response(refresh_conn, 401)
    end

    test "POST /api/v1/auth/deactivate", %{auth_conn: conn, refresh_token: refresh_token} do
      conn = post(conn, ~p"/api/v1/auth/deactivate", %{"refresh_token" => refresh_token})
      assert response(conn, 204)

      refresh_conn =
        post(build_conn(), ~p"/api/v1/auth/refresh", %{"refresh_token" => refresh_token})

      assert json_response(refresh_conn, 401)
    end
  end
end
