defmodule AuthWeb.AuthControllerTest do
  use AuthWeb.ConnCase, async: true

  import Auth.AccountsFixtures

  alias Auth.Accounts
  alias Auth.Token.Keys

  defp register_params(overrides) do
    %{
      "username" => "newuser",
      "email" => "new@example.com",
      "password" => default_password(),
      "birthday" => "2000-01-31",
      "tos_agreed" => true
    }
    |> Map.merge(overrides)
  end

  describe "POST /api/v1/auth/register" do
    test "creates a user and returns a session", %{conn: conn} do
      ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)
      conn = post(conn, ~p"/api/v1/auth/register", register_params(%{}))

      assert %{
               "access_token" => token,
               "token_type" => "Bearer",
               "expires_in" => ^ttl,
               "user" => %{
                 "user_id" => user_id,
                 "username" => "newuser",
                 "email" => "new@example.com",
                 "email_verified" => false
               }
             } = json_response(conn, 201)

      assert is_binary(token)
      assert user_id
      refute Map.has_key?(json_response(conn, 201), "refresh_token")
    end

    test "returns a refresh token when remember_me is set", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/register", register_params(%{"remember_me" => true}))

      assert %{"refresh_token" => refresh_token} = json_response(conn, 201)
      assert is_binary(refresh_token)
    end

    test "returns 422 with field list for missing params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/register", %{"email" => "only@example.com"})

      assert %{"errors" => %{"fields" => fields}} = json_response(conn, 422)
      assert Map.has_key?(fields, "username")
      assert Map.has_key?(fields, "password")
      assert Map.has_key?(fields, "birthday")
      assert Map.has_key?(fields, "tos_agreed")
    end

    test "returns generic error for duplicate email", %{conn: conn} do
      user_fixture(%{email: "dup@example.com"})

      conn =
        post(conn, ~p"/api/v1/auth/register", register_params(%{"email" => "dup@example.com"}))

      assert %{"errors" => %{"detail" => "could not create account"}} = json_response(conn, 422)
      refute json_response(conn, 422)["errors"]["fields"]
    end

    test "returns 422 with field errors for weak password", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/register", register_params(%{"password" => "password1"}))

      assert %{"errors" => %{"fields" => %{"password" => messages}}} = json_response(conn, 422)
      assert Enum.any?(messages, &(&1 =~ "uppercase"))
    end

    test "returns 422 when TOS is not agreed", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/register", register_params(%{"tos_agreed" => false}))

      assert %{"errors" => %{"fields" => %{"tos_agreed" => [_ | _]}}} = json_response(conn, 422)
    end
  end

  describe "POST /api/v1/auth/login" do
    setup do
      user_fixture(%{username: "api_user", email: "api@example.com"})
      :ok
    end

    test "logs in with email identifier", %{conn: conn} do
      ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)

      conn =
        post(conn, ~p"/api/v1/auth/login", %{
          "identifier" => "api@example.com",
          "password" => default_password()
        })

      assert %{
               "access_token" => token,
               "token_type" => "Bearer",
               "expires_in" => ^ttl,
               "user" => %{"username" => "api_user"}
             } = json_response(conn, 200)

      assert is_binary(token)
    end

    test "logs in with username identifier and remember_me", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/login", %{
          "identifier" => "api_user",
          "password" => default_password(),
          "remember_me" => true
        })

      assert %{"refresh_token" => refresh_token} = json_response(conn, 200)
      assert is_binary(refresh_token)
    end

    test "returns same error for invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/login", %{
          "identifier" => "api@example.com",
          "password" => "Wrong-password1"
        })

      assert %{"errors" => %{"detail" => "Invalid username/email or password"}} =
               json_response(conn, 401)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    setup do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      %{refresh_token: session.refresh_token}
    end

    test "returns a new access token and rotated refresh token", %{
      conn: conn,
      refresh_token: refresh_token
    } do
      conn = post(conn, ~p"/api/v1/auth/refresh", %{"refresh_token" => refresh_token})

      assert %{"access_token" => token, "refresh_token" => new_refresh_token} =
               json_response(conn, 200)

      assert is_binary(token)
      assert is_binary(new_refresh_token)
      assert new_refresh_token != refresh_token
    end

    test "returns 401 for an unknown token", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/refresh", %{"refresh_token" => "bogus"})
      assert json_response(conn, 401)
    end

    test "returns 401 when token is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/refresh", %{})
      assert json_response(conn, 401)
    end
  end

  describe "authenticated routes" do
    setup %{conn: conn} do
      user = user_fixture(%{username: "me_user", email: "me@example.com"})

      conn =
        post(conn, ~p"/api/v1/auth/login", %{
          "identifier" => "me@example.com",
          "password" => default_password(),
          "remember_me" => true
        })

      body = json_response(conn, 200)
      access_token = body["access_token"]
      auth_conn = put_req_header(build_conn(), "authorization", "Bearer " <> access_token)

      %{
        auth_conn: auth_conn,
        refresh_token: body["refresh_token"],
        access_token: access_token,
        user: user
      }
    end

    test "GET /api/v1/auth/me includes username", %{auth_conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/me")

      assert %{
               "user_id" => _,
               "username" => "me_user",
               "email" => "me@example.com",
               "status" => "active",
               "email_verified" => false
             } = json_response(conn, 200)
    end

    test "POST /api/v1/auth/logout revokes the refresh token too", %{
      auth_conn: conn,
      refresh_token: refresh_token
    } do
      conn = post(conn, ~p"/api/v1/auth/logout", %{"refresh_token" => refresh_token})
      assert response(conn, 204)

      refresh_conn =
        post(build_conn(), ~p"/api/v1/auth/refresh", %{"refresh_token" => refresh_token})

      assert json_response(refresh_conn, 401)
    end

    test "rejects missing bearer token" do
      conn = get(build_conn(), ~p"/api/v1/auth/me")
      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end

    test "returns 401 for a malformed bearer token" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer not-a-jwt")
        |> get(~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end

    test "returns 401 for an expired bearer token", %{user: user} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> expired_access_token(user))
        |> get(~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end

    test "returns 401 for a bearer token with an invalid signature", %{access_token: access_token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> tamper_jwt_signature(access_token))
        |> get(~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end

    test "returns 401 for a bearer token with an unknown subject" do
      conn =
        build_conn()
        |> put_req_header(
          "authorization",
          "Bearer " <> access_token_for_subject(Ecto.UUID.generate())
        )
        |> get(~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 for a suspended user with a valid token", %{auth_conn: conn, user: user} do
      {:ok, _} =
        user
        |> Ash.Changeset.for_update(:set_status, %{status: :suspended})
        |> Ash.update()

      conn = get(conn, ~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "returns 401 for a deleted user with a valid token", %{auth_conn: conn, user: user} do
      {:ok, _} =
        user
        |> Ash.Changeset.for_update(:set_status, %{status: :deleted})
        |> Ash.update()

      conn = get(conn, ~p"/api/v1/auth/me")

      assert %{"errors" => %{"detail" => "Unauthorized"}} = json_response(conn, 401)
    end
  end

  defp expired_access_token(user) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "sub" => user.id,
      "status" => to_string(user.status),
      "jti" => Ecto.UUID.generate(),
      "exp" => now - 60,
      "iat" => now - 120,
      "nbf" => now - 120
    }

    {:ok, token, _claims} =
      Joken.generate_and_sign(
        access_token_config(skip: [:exp, :iat, :nbf]),
        claims,
        Keys.signer()
      )

    token
  end

  defp access_token_for_subject(subject) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "sub" => subject,
      "status" => "active",
      "jti" => Ecto.UUID.generate(),
      "exp" => now + 60,
      "iat" => now,
      "nbf" => now
    }

    {:ok, token, _claims} = Joken.generate_and_sign(access_token_config(), claims, Keys.signer())

    token
  end

  defp access_token_config(opts \\ []) do
    ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)
    issuer = Application.fetch_env!(:auth, :jwt_issuer)
    audience = Application.fetch_env!(:auth, :jwt_audience)
    skip = Keyword.get(opts, :skip, [])

    Joken.Config.default_claims(default_exp: ttl, iss: issuer, aud: audience, skip: skip)
    |> Joken.Config.add_claim("sub", fn -> nil end, &valid_uuid?/1)
    |> Joken.Config.add_claim("status", fn -> nil end, &valid_status?/1)
    |> Joken.Config.add_claim("jti", fn -> nil end, &valid_uuid?/1)
  end

  defp valid_uuid?(value) when is_binary(value) do
    match?({:ok, _}, Ecto.UUID.cast(value))
  end

  defp valid_uuid?(_value), do: false

  defp valid_status?(value) when value in ["active", "suspended", "deleted"], do: true
  defp valid_status?(_value), do: false

  defp tamper_jwt_signature(token) do
    [header, payload, signature] = String.split(token, ".", parts: 3)
    <<first::binary-size(1), rest::binary>> = signature
    tampered_first = if first == "a", do: "b", else: "a"
    Enum.join([header, payload, tampered_first <> rest], ".")
  end
end
