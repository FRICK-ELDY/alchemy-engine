defmodule Network.S2STest do
  use ExUnit.Case, async: false

  require Phoenix.ConnTest

  alias Network.S2S.{Catalog, Client, Instance}

  @endpoint Network.Endpoint
  @local_domain "local.test"
  @peer_domain "peer.test"

  setup do
    previous = Application.get_env(:network, Network.S2S, [])

    on_exit(fn ->
      Application.put_env(:network, Network.S2S, previous)
      _ = Instance.configure(previous)
    end)

    :ok
  end

  describe "disabled (default)" do
    test "well-known は 404" do
      conn = Phoenix.ConnTest.get(Phoenix.ConnTest.build_conn(), "/.well-known/alchemy-s2s.json")
      assert %{"error" => "s2s_disabled"} = Phoenix.ConnTest.json_response(conn, 404)
    end

    test "worlds は 404" do
      conn = Phoenix.ConnTest.get(Phoenix.ConnTest.build_conn(), "/api/s2s/worlds")
      assert %{"error" => "s2s_disabled"} = Phoenix.ConnTest.json_response(conn, 404)
    end
  end

  describe "enabled instance" do
    setup do
      worlds = [
        %{id: "alpha", title: "Alpha", status: "General", path: "/worlds/alpha"},
        %{id: "explicit", title: "X", status: "Explicit", path: "/worlds/x"}
      ]

      cfg = [
        enabled: true,
        domain: @local_domain,
        canonical_url: "http://local.test",
        max_content_status: "General",
        ephemeral_keys: true,
        worlds: worlds,
        peers: []
      ]

      Application.put_env(:network, Network.S2S, cfg)
      assert :ok = Instance.configure(cfg)
      :ok
    end

    test "well-known に domain と JWKS が載る" do
      conn = Phoenix.ConnTest.get(Phoenix.ConnTest.build_conn(), "/.well-known/alchemy-s2s.json")
      assert body = Phoenix.ConnTest.json_response(conn, 200)
      assert body["domain"] == @local_domain
      assert [%{"kid" => kid, "alg" => "RS256"}] = body["jwks"]["keys"]
      assert is_binary(kid)
    end

    test "Catalog は max_content_status でフィルタする" do
      worlds = Catalog.list_worlds()
      assert Enum.map(worlds, & &1["id"]) == ["alpha"]
      assert hd(worlds)["uri"] == "http://local.test/worlds/alpha"
    end

    test "署名なし worlds は 401" do
      conn = Phoenix.ConnTest.get(Phoenix.ConnTest.build_conn(), "/api/s2s/worlds")
      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
    end

    test "ピア署名付き JWT でワールド一覧を取得できる" do
      {kid, pem, jwks} = generate_rsa_jwks()
      :ok = Instance.put_peer_jwks(@peer_domain, jwks)
      token = sign_s2s_token(pem, kid, @peer_domain, @local_domain)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert body = Phoenix.ConnTest.json_response(conn, 200)
      assert body["domain"] == @local_domain
      assert body["caller"] == @peer_domain
      assert [%{"id" => "alpha", "title" => "Alpha"}] = body["worlds"]
    end

    test "aud 不一致は拒否" do
      {kid, pem, jwks} = generate_rsa_jwks()
      :ok = Instance.put_peer_jwks(@peer_domain, jwks)
      token = sign_s2s_token(pem, kid, @peer_domain, "other.domain")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
    end

    test "Client.fetch_worlds が署名して取得する" do
      remote_body = %{
        "domain" => @peer_domain,
        "worlds" => [%{"id" => "remote", "title" => "Remote", "status" => "General"}],
        "caller" => @local_domain
      }

      get_fun = fn
        url, nil ->
          assert String.ends_with?(url, "/.well-known/alchemy-s2s.json")
          {:ok, %{"domain" => @peer_domain}}

        url, token when is_binary(token) ->
          assert String.ends_with?(url, "/api/s2s/worlds")
          assert {:ok, claims} = Joken.peek_claims(token)
          assert claims["iss"] == @local_domain
          assert claims["aud"] == @peer_domain
          assert claims["purpose"] == Instance.purpose_worlds_read()
          {:ok, remote_body}
      end

      assert {:ok, body} =
               Client.fetch_worlds("http://peer.test", audience: @peer_domain, get_fun: get_fun)

      assert [%{"id" => "remote"}] = body["worlds"]
    end

    test "iss が HTTP URL でも未設定ピアなら fetch せず拒否する（SSRF）" do
      fetch_count = :counters.new(1, [])

      cfg = [
        enabled: true,
        domain: @local_domain,
        canonical_url: "http://local.test",
        ephemeral_keys: true,
        worlds: [],
        peers: [],
        fetch_fun: fn _url ->
          :counters.add(fetch_count, 1, 1)
          {:ok, %{"keys" => []}}
        end
      ]

      Application.put_env(:network, Network.S2S, cfg)
      assert :ok = Instance.configure(cfg)

      {kid, pem, _jwks} = generate_rsa_jwks()
      token = sign_s2s_token(pem, kid, "http://169.254.169.254", @local_domain)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
      assert :counters.get(fetch_count, 1) == 0
    end

    test "設定済みピアの未知 kid は JWKS 再取得で鍵ローテに追従する" do
      {kid1, pem1, jwks1} = generate_rsa_jwks()
      {kid2, pem2, jwks2} = generate_rsa_jwks()
      fetch_count = :counters.new(1, [])

      cfg = [
        enabled: true,
        domain: @local_domain,
        canonical_url: "http://local.test",
        ephemeral_keys: true,
        worlds: [%{id: "alpha", title: "Alpha", status: "General", path: "/w"}],
        peers: [%{domain: @peer_domain, jwks_url: "http://peer.test/jwks", jwks: jwks1}],
        fetch_fun: fn url ->
          assert url == "http://peer.test/jwks"
          :counters.add(fetch_count, 1, 1)
          {:ok, jwks2}
        end
      ]

      Application.put_env(:network, Network.S2S, cfg)
      assert :ok = Instance.configure(cfg)

      # 初回: 静的 JWKS の鍵で成功（fetch なし）
      token1 = sign_s2s_token(pem1, kid1, @peer_domain, @local_domain)

      conn1 =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token1}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert %{"caller" => @peer_domain} = Phoenix.ConnTest.json_response(conn1, 200)
      assert :counters.get(fetch_count, 1) == 0

      # ローテ後の kid: 再取得して受け入れる
      token2 = sign_s2s_token(pem2, kid2, @peer_domain, @local_domain)

      conn2 =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token2}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert %{"caller" => @peer_domain} = Phoenix.ConnTest.json_response(conn2, 200)
      assert :counters.get(fetch_count, 1) == 1
    end

    test "不正な JWKS keys でも GenServer が落ちない" do
      fetch_count = :counters.new(1, [])

      cfg = [
        enabled: true,
        domain: @local_domain,
        canonical_url: "http://local.test",
        ephemeral_keys: true,
        worlds: [],
        peers: [%{domain: @peer_domain, jwks_url: "http://peer.test/jwks"}],
        fetch_fun: fn _url ->
          :counters.add(fetch_count, 1, 1)
          {:ok, %{"keys" => "not-a-list"}}
        end
      ]

      Application.put_env(:network, Network.S2S, cfg)
      assert :ok = Instance.configure(cfg)

      {kid, pem, _jwks} = generate_rsa_jwks()
      token = sign_s2s_token(pem, kid, @peer_domain, @local_domain)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Phoenix.ConnTest.get("/api/s2s/worlds")

      assert %{"error" => "unauthorized"} = Phoenix.ConnTest.json_response(conn, 401)
      assert Process.whereis(Instance)
      assert :counters.get(fetch_count, 1) == 1
    end

    test "enabled 時に domain 欠落なら configure が失敗する" do
      assert {:error, {:s2s_config_invalid, :missing_domain}} =
               Instance.configure(
                 enabled: true,
                 domain: "",
                 ephemeral_keys: true,
                 worlds: []
               )

      # 失敗後も前回設定で生存している
      assert Instance.enabled?()
      assert Instance.runtime_config()[:domain] == @local_domain
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

  defp sign_s2s_token(private_pem, kid, iss, aud) do
    signer = Joken.Signer.create("RS256", %{"pem" => private_pem}, %{"kid" => kid})
    now = System.system_time(:second)

    claims = %{
      "iss" => iss,
      "aud" => aud,
      "sub" => "alchemy-s2s",
      "iat" => now,
      "exp" => now + 300,
      "purpose" => Instance.purpose_worlds_read()
    }

    {:ok, token, _} =
      Joken.generate_and_sign(
        Joken.Config.default_claims(skip: [:iss, :aud, :exp, :iat, :nbf, :jti]),
        claims,
        signer
      )

    token
  end
end
