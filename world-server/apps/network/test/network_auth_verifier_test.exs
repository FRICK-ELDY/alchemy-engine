defmodule Network.AuthVerifierTest do
  use ExUnit.Case, async: false

  require Phoenix.ConnTest

  alias Network.AuthVerifier

  @endpoint Network.Endpoint
  @issuer "alchemy-auth"
  @audience "alchemy-platform"

  setup do
    {kid, private_pem, jwks} = generate_rsa_jwks()
    :ok = AuthVerifier.put_jwks(jwks)

    on_exit(fn ->
      Application.put_env(:network, :auth_required, false)
    end)

    %{kid: kid, private_pem: private_pem, jwks: jwks}
  end

  describe "verify/1" do
    test "有効な RS256 JWT を受け入れる", %{private_pem: pem, kid: kid} do
      token = sign_token(pem, kid)

      assert {:ok, claims} = AuthVerifier.verify(token)
      assert claims["iss"] == @issuer
      assert claims["aud"] == @audience
      assert claims["status"] == "active"
    end

    test "alg が RS256 以外なら拒否する", %{private_pem: pem, kid: kid} do
      # ヘッダだけ差し替えた不正トークンは署名検証前に alg で落ちる
      # HS256 風に別 signer で署名すると kid の RSA signer と不一致になるが、
      # まずは alg チェックを通すため peek 可能なトークンを手組みする。
      header =
        %{"alg" => "none", "kid" => kid}
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)

      payload =
        default_claims()
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)

      token = header <> "." <> payload <> ".x"

      assert {:error, :invalid_alg} = AuthVerifier.verify(token)
      # silence unused
      _ = pem
    end

    test "未知の kid は拒否する", %{private_pem: _pem} do
      {_kid2, pem2, _jwks2} = generate_rsa_jwks()
      # 別鍵で署名するが JWKS には載せない
      jwk = JOSE.JWK.from_pem(pem2)
      public = JOSE.JWK.to_public(jwk)
      kid2 = jose_thumbprint(public)
      token = sign_token(pem2, kid2)

      assert {:error, :unknown_kid} = AuthVerifier.verify(token)
    end

    test "status が active 以外は拒否する", %{private_pem: pem, kid: kid} do
      token = sign_token(pem, kid, %{"status" => "suspended"})
      assert {:error, :inactive_status} = AuthVerifier.verify(token)
    end

    test "期限切れ JWT は拒否する", %{private_pem: pem, kid: kid} do
      now = System.system_time(:second)
      token = sign_token(pem, kid, %{"iat" => now - 120, "exp" => now - 90})
      assert {:error, {:token_validation_failed, _}} = AuthVerifier.verify(token)
    end

    test "aud 配列に期待値が含まれていれば受け入れる", %{private_pem: pem, kid: kid} do
      token = sign_token(pem, kid, %{"aud" => [@audience, "other"]})
      assert {:ok, _} = AuthVerifier.verify(token)
    end
  end

  describe "POST /api/room_token with AUTH_REQUIRED" do
    test "オフ時は Bearer なしで発行できる" do
      Application.put_env(:network, :auth_required, false)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Phoenix.ConnTest.post("/api/room_token", Jason.encode!(%{room_id: "demo"}))

      assert %{"token" => token} = Phoenix.ConnTest.json_response(conn, 200)
      assert is_binary(token)
    end

    test "オン時は Bearer なしで 401", %{private_pem: _pem} do
      Application.put_env(:network, :auth_required, true)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Phoenix.ConnTest.post("/api/room_token", Jason.encode!(%{room_id: "demo"}))

      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
    end

    test "オン時は有効 JWT で発行できる", %{private_pem: pem, kid: kid} do
      Application.put_env(:network, :auth_required, true)
      jwt = sign_token(pem, kid)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{jwt}")
        |> Phoenix.ConnTest.post("/api/room_token", Jason.encode!(%{room_id: "secured"}))

      assert %{"token" => token} = Phoenix.ConnTest.json_response(conn, 200)
      assert :ok = Network.RoomToken.verify(token, "secured")
    end

    test "オン時は不正 JWT で 401", %{private_pem: pem, kid: kid} do
      Application.put_env(:network, :auth_required, true)
      jwt = sign_token(pem, kid, %{"status" => "deleted"})

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{jwt}")
        |> Phoenix.ConnTest.post("/api/room_token", Jason.encode!(%{room_id: "secured"}))

      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────

  defp generate_rsa_jwks do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_type, private_pem} = JOSE.JWK.to_pem(jwk)
    public = JOSE.JWK.to_public(jwk)
    kid = jose_thumbprint(public)
    {_fields, jwk_map} = JOSE.JWK.to_map(public)

    jwks = %{
      "keys" => [
        jwk_map
        |> Map.put("kid", kid)
        |> Map.put("use", "sig")
        |> Map.put("alg", "RS256")
      ]
    }

    {kid, private_pem, jwks}
  end

  defp jose_thumbprint(public_jwk) do
    case JOSE.JWK.thumbprint(public_jwk) do
      {:kid, kid} -> kid
      kid when is_binary(kid) -> kid
    end
  end

  defp sign_token(private_pem, kid, extra \\ %{}) do
    signer = Joken.Signer.create("RS256", %{"pem" => private_pem}, %{"kid" => kid})
    claims = Map.merge(default_claims(), extra)

    {:ok, token, _} =
      Joken.generate_and_sign(
        Joken.Config.default_claims(skip: [:iss, :aud, :exp, :iat, :nbf, :jti]),
        claims,
        signer
      )

    token
  end

  defp default_claims do
    now = System.system_time(:second)

    %{
      "sub" => "11111111-1111-4111-8111-111111111111",
      "iss" => @issuer,
      "aud" => @audience,
      "iat" => now,
      "exp" => now + 3600,
      "jti" => "22222222-2222-4222-8222-222222222222",
      "status" => "active"
    }
  end
end
