defmodule Auth.TokenTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures

  alias Auth.Accounts
  alias Auth.Token
  alias Auth.Token.Keys

  setup do
    %{user: user_fixture(%{email: "token@example.com"})}
  end

  test "generates and verifies a token", %{user: user} do
    ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)
    assert {:ok, token, _jti, ^ttl} = Token.generate(user)
    assert {:ok, claims, verified_user} = Token.verify(token)
    assert claims["sub"] == user.id
    assert verified_user.id == user.id
    assert claims["status"] == "active"
    assert claims["iss"] == "alchemy-auth"
    assert claims["aud"] == "alchemy-platform"
    assert is_binary(claims["jti"])
  end

  test "includes kid in JWT header matching JWKS", %{user: user} do
    assert {:ok, token, _jti, _} = Token.generate(user)

    [header_b64 | _] = String.split(token, ".")
    header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
    jwk_kid = Keys.jwks() |> Map.fetch!("keys") |> List.first() |> Map.fetch!("kid")

    assert header["kid"] == jwk_kid
  end

  test "rejects revoked token", %{user: user} do
    assert {:ok, token, jti, _expires_in} = Token.generate(user)
    expires_at = DateTime.utc_now() |> DateTime.add(86_400, :second)

    assert {:ok, _} = Accounts.logout(jti, user.id, expires_at)
    assert {:error, :revoked} = Token.verify(token)
  end

  test "rejects token with unknown kid", %{user: user} do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_type, pem} = JOSE.JWK.to_pem(jwk)
    foreign_signer = Joken.Signer.create("RS256", %{"pem" => pem}, %{"kid" => "foreign-kid"})

    extra_claims = %{
      "sub" => user.id,
      "status" => "active",
      "jti" => Ecto.UUID.generate()
    }

    ttl = Application.fetch_env!(:auth, :jwt_ttl_seconds)
    issuer = Application.fetch_env!(:auth, :jwt_issuer)
    audience = Application.fetch_env!(:auth, :jwt_audience)

    config =
      Joken.Config.default_claims(default_exp: ttl, iss: issuer, aud: audience)
      |> Joken.Config.add_claim("sub", fn -> nil end, fn _ -> true end)
      |> Joken.Config.add_claim("status", fn -> nil end, fn _ -> true end)
      |> Joken.Config.add_claim("jti", fn -> nil end, fn _ -> true end)

    assert {:ok, token, _} = Joken.generate_and_sign(config, extra_claims, foreign_signer)
    assert {:error, :unknown_kid} = Token.verify(token)
  end
end
