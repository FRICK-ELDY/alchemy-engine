defmodule Network.S2S.Instance do
  @moduledoc """
  連合層のローカル・インスタンス自己記述と S2S 署名鍵。

  - `config :network, Network.S2S` でドメイン・鍵・ワールドメタデータをリソース化
  - `GET /.well-known/alchemy-s2s.json` 向けの公開記述を提供
  - 他インスタンス呼び出し用の短命 RS256 JWT を署名・検証する

  `enabled: false`（既定）のときは連合 API を公開しない（デモ経路に影響しない）。
  """

  use GenServer
  require Logger

  @purpose_worlds_read "s2s.worlds.read"
  @token_ttl_seconds 300
  @skew_seconds 60

  # ── Public API ───────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "連合 S2S が有効か。"
  @spec enabled?() :: boolean()
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  catch
    :exit, {:noproc, _} -> Keyword.get(config(), :enabled, false) == true
  end

  @doc "Application 設定を返す。"
  @spec config() :: keyword()
  def config do
    Application.get_env(:network, Network.S2S, [])
  end

  @doc """
  実行中インスタンスのカタログ用スナップショット。

  `start_link/1` の opts で上書きした値を含む。
  """
  @spec runtime_config() :: keyword()
  def runtime_config do
    GenServer.call(__MODULE__, :runtime_config)
  catch
    :exit, {:noproc, _} -> config()
  end

  @doc """
  公開自己記述（well-known）。

  `enabled: false` のときは `{:error, :disabled}`。
  """
  @spec describe() :: {:ok, map()} | {:error, :disabled | :not_ready}
  def describe do
    GenServer.call(__MODULE__, :describe)
  catch
    :exit, {:noproc, _} -> {:error, :not_ready}
  end

  @doc "呼び出し元インスタンスとしてリクエスト JWT を署名する。"
  @spec sign_request_token(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def sign_request_token(audience, purpose \\ @purpose_worlds_read)
      when is_binary(audience) and is_binary(purpose) do
    GenServer.call(__MODULE__, {:sign_request_token, audience, purpose})
  catch
    :exit, {:noproc, _} -> {:error, :not_ready}
  end

  @doc "他インスタンスからのリクエスト JWT を検証する。"
  @spec verify_request_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_request_token(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:verify_request_token, token})
  catch
    :exit, {:noproc, _} -> {:error, :not_ready}
  end

  @doc false
  @spec put_peer_jwks(String.t(), map()) :: :ok
  def put_peer_jwks(domain, %{"keys" => _} = jwks) when is_binary(domain) do
    GenServer.call(__MODULE__, {:put_peer_jwks, domain, jwks})
  end

  @doc false
  @spec configure(keyword()) :: :ok | {:error, term()}
  def configure(opts) when is_list(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  catch
    :exit, {:noproc, _} -> {:error, :not_ready}
  end

  @doc false
  @spec purpose_worlds_read() :: String.t()
  def purpose_worlds_read, do: @purpose_worlds_read

  # ── GenServer ────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    case build_state(opts) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled == true, state}
  end

  def handle_call(:runtime_config, _from, state) do
    cfg = [
      enabled: state.enabled,
      domain: state.domain,
      canonical_url: state.canonical_url,
      max_content_status: state.max_content_status,
      worlds: state.worlds
    ]

    {:reply, cfg, state}
  end

  def handle_call(:describe, _from, state) do
    if state.enabled and is_map(state.public_jwk) do
      body = %{
        "domain" => state.domain,
        "canonical_url" => state.canonical_url,
        "max_content_status" => state.max_content_status,
        "jwks" => %{"keys" => [state.public_jwk]}
      }

      {:reply, {:ok, body}, state}
    else
      {:reply, {:error, :disabled}, state}
    end
  end

  def handle_call({:sign_request_token, audience, purpose}, _from, state) do
    reply =
      cond do
        not state.enabled ->
          {:error, :disabled}

        is_nil(state.signer) or not is_binary(state.domain) ->
          {:error, :not_ready}

        true ->
          now = System.system_time(:second)

          claims = %{
            "iss" => state.domain,
            "aud" => audience,
            "sub" => "alchemy-s2s",
            "iat" => now,
            "exp" => now + @token_ttl_seconds,
            "purpose" => purpose
          }

          case Joken.generate_and_sign(token_config_for_sign(), claims, state.signer) do
            {:ok, token, _} -> {:ok, token}
            {:error, reason} -> {:error, reason}
          end
      end

    {:reply, reply, state}
  end

  def handle_call({:verify_request_token, token}, _from, state) do
    {reply, new_state} = do_verify(token, state)
    {:reply, reply, new_state}
  end

  def handle_call({:put_peer_jwks, domain, jwks}, _from, state) do
    {:reply, :ok, apply_peer_jwks(state, domain, jwks)}
  end

  def handle_call({:configure, opts}, _from, state) do
    case build_state(opts) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp build_state(opts) do
    cfg = Keyword.merge(config(), opts)

    state = %{
      enabled: Keyword.get(cfg, :enabled, false) == true,
      domain: Keyword.get(cfg, :domain),
      canonical_url: Keyword.get(cfg, :canonical_url),
      max_content_status: Keyword.get(cfg, :max_content_status, "General"),
      worlds: Keyword.get(cfg, :worlds, []),
      peers: normalize_peers(Keyword.get(cfg, :peers, [])),
      fetch_fun: Keyword.get(cfg, :fetch_fun, &default_fetch/1),
      signer: nil,
      kid: nil,
      public_jwk: nil,
      peer_signers: %{},
      peer_fetched_at: %{}
    }

    state =
      case load_or_generate_keys(cfg, state.enabled) do
        {:ok, kid, signer, public_jwk} ->
          %{state | kid: kid, signer: signer, public_jwk: public_jwk}

        {:error, reason} ->
          if state.enabled do
            Logger.error("[S2S.Instance] key load failed: #{inspect(reason)}")
          end

          state
      end

    if state.enabled and is_nil(state.signer) do
      {:error, {:s2s_keys_unavailable, :missing_private_key}}
    else
      {:ok, seed_static_peer_jwks(state)}
    end
  end

  # ── verify / peers ───────────────────────────────────────────────

  defp do_verify(_token, %{enabled: false} = state), do: {{:error, :disabled}, state}

  defp do_verify(token, state) do
    with {:ok, header} <- peek_header(token),
         :ok <- check_alg(header),
         {:ok, claims_map} <- peek_claims(token),
         :ok <- check_aud(claims_map, state.domain),
         :ok <- check_purpose(claims_map),
         {:ok, iss} <- fetch_iss(claims_map),
         {:ok, state2, signer} <- resolve_peer_signer(state, iss, header["kid"]),
         {:ok, claims} <-
           Joken.verify_and_validate(token_config_for_verify(state.domain), token, signer) do
      {{:ok, claims}, state2}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  defp peek_header(token) do
    case Joken.peek_header(token) do
      {:ok, header} -> {:ok, header}
      {:error, reason} -> {:error, {:invalid_token, reason}}
    end
  end

  defp peek_claims(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, {:invalid_token, reason}}
    end
  end

  defp check_alg(%{"alg" => "RS256"}), do: :ok
  defp check_alg(_), do: {:error, :invalid_alg}

  defp check_aud(%{"aud" => aud}, domain) when is_binary(domain) do
    if aud_matches?(aud, domain), do: :ok, else: {:error, :aud_mismatch}
  end

  defp check_aud(_, _), do: {:error, :aud_mismatch}

  defp check_purpose(%{"purpose" => @purpose_worlds_read}), do: :ok
  defp check_purpose(_), do: {:error, :invalid_purpose}

  defp fetch_iss(%{"iss" => iss}) when is_binary(iss) and iss != "", do: {:ok, iss}
  defp fetch_iss(_), do: {:error, :missing_iss}

  defp resolve_peer_signer(state, iss, kid) do
    case Map.get(state.peer_signers, iss) do
      %{} = by_kid when map_size(by_kid) > 0 ->
        pick_signer(state, iss, by_kid, kid)

      _ ->
        case fetch_peer_jwks(state, iss) do
          {:ok, new_state} ->
            by_kid = Map.get(new_state.peer_signers, iss, %{})
            pick_signer(new_state, iss, by_kid, kid)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp pick_signer(state, _iss, by_kid, kid) when is_binary(kid) do
    case Map.fetch(by_kid, kid) do
      {:ok, signer} -> {:ok, state, signer}
      :error -> {:error, :unknown_kid}
    end
  end

  defp pick_signer(_state, _iss, _by_kid, _), do: {:error, :missing_kid}

  defp fetch_peer_jwks(state, iss) do
    case peer_well_known_url(state, iss) do
      nil ->
        {:error, :unknown_peer}

      url ->
        case state.fetch_fun.(url) do
          {:ok, %{"jwks" => %{"keys" => _} = jwks}} ->
            {:ok, apply_peer_jwks(state, iss, jwks)}

          {:ok, %{"keys" => _} = jwks} ->
            {:ok, apply_peer_jwks(state, iss, jwks)}

          {:ok, _} ->
            {:error, :invalid_peer_document}

          {:error, reason} ->
            {:error, {:peer_fetch_failed, reason}}
        end
    end
  end

  defp peer_well_known_url(state, iss) do
    case Enum.find(state.peers, fn p -> p.domain == iss end) do
      %{canonical_url: url} when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/") <> "/.well-known/alchemy-s2s.json"

      %{jwks_url: url} when is_binary(url) and url != "" ->
        url

      _ ->
        if looks_like_http_url?(iss) do
          String.trim_trailing(iss, "/") <> "/.well-known/alchemy-s2s.json"
        else
          nil
        end
    end
  end

  defp looks_like_http_url?(s), do: String.starts_with?(s, "http://") or String.starts_with?(s, "https://")

  defp apply_peer_jwks(state, domain, %{"keys" => keys}) do
    signers =
      keys
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(fn jwk ->
        kid = jwk["kid"]

        if is_binary(kid) and kid != "" do
          try do
            jose_jwk = JOSE.JWK.from_map(jwk)
            {_type, pem} = JOSE.JWK.to_pem(jose_jwk)
            [{kid, Joken.Signer.create("RS256", %{"pem" => pem}, %{"kid" => kid})}]
          rescue
            _ -> []
          end
        else
          []
        end
      end)
      |> Map.new()

    %{
      state
      | peer_signers: Map.put(state.peer_signers, domain, signers),
        peer_fetched_at: Map.put(state.peer_fetched_at, domain, System.monotonic_time(:millisecond))
    }
  end

  defp seed_static_peer_jwks(state) do
    Enum.reduce(state.peers, state, fn
      %{domain: domain, jwks: %{"keys" => _} = jwks}, acc ->
        apply_peer_jwks(acc, domain, jwks)

      _, acc ->
        acc
    end)
  end

  defp normalize_peers(peers) when is_list(peers) do
    Enum.flat_map(peers, fn
      %{} = p ->
        domain = peer_get(p, :domain) || peer_get(p, "domain")

        if is_binary(domain) and domain != "" do
          [
            %{
              domain: domain,
              canonical_url: peer_get(p, :canonical_url) || peer_get(p, "canonical_url"),
              jwks_url: peer_get(p, :jwks_url) || peer_get(p, "jwks_url"),
              jwks: peer_get(p, :jwks) || peer_get(p, "jwks")
            }
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp peer_get(map, key), do: Map.get(map, key)

  # ── keys ─────────────────────────────────────────────────────────

  defp load_or_generate_keys(cfg, enabled?) do
    pem = Keyword.get(cfg, :private_key_pem)
    path = Keyword.get(cfg, :private_key_path)

    cond do
      is_binary(pem) and String.trim(pem) != "" ->
        from_pem(pem)

      is_binary(path) and String.trim(path) != "" ->
        case File.read(path) do
          {:ok, contents} -> from_pem(contents)
          {:error, reason} -> {:error, reason}
        end

      enabled? and Keyword.get(cfg, :ephemeral_keys, false) == true ->
        generate_ephemeral()

      enabled? ->
        # 開発利便性: 鍵未設定ならエフェメラル鍵（再起動で変わる）
        Logger.warning(
          "[S2S.Instance] no private key configured; generating ephemeral RSA key (dev only)"
        )

        generate_ephemeral()

      true ->
        {:error, :disabled}
    end
  end

  defp from_pem(pem) do
    jwk = JOSE.JWK.from_pem(pem)
    public = JOSE.JWK.to_public(jwk)
    kid = jose_thumbprint(public)
    {_fields, jwk_map} = JOSE.JWK.to_map(public)

    public_jwk =
      jwk_map
      |> Map.put("kid", kid)
      |> Map.put("use", "sig")
      |> Map.put("alg", "RS256")

    signer = Joken.Signer.create("RS256", %{"pem" => pem}, %{"kid" => kid})
    {:ok, kid, signer, public_jwk}
  rescue
    e -> {:error, e}
  end

  defp generate_ephemeral do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_type, private_pem} = JOSE.JWK.to_pem(jwk)
    from_pem(private_pem)
  end

  defp jose_thumbprint(public_jwk) do
    case JOSE.JWK.thumbprint(public_jwk) do
      {:kid, kid} -> kid
      kid when is_binary(kid) -> kid
    end
  end

  # ── Joken configs ────────────────────────────────────────────────

  defp token_config_for_sign do
    Joken.Config.default_claims(skip: [:iss, :aud, :exp, :iat, :nbf, :jti])
  end

  defp token_config_for_verify(local_domain) do
    now_fun = fn -> System.system_time(:second) end

    Joken.Config.default_claims(skip: [:iss, :aud, :exp, :iat, :nbf, :jti])
    |> Joken.Config.add_claim("iss", fn -> nil end, &(is_binary(&1) and &1 != ""))
    |> Joken.Config.add_claim("aud", fn -> nil end, &aud_matches?(&1, local_domain))
    |> Joken.Config.add_claim("sub", fn -> nil end, &(&1 == "alchemy-s2s"))
    |> Joken.Config.add_claim("exp", fn -> nil end, &valid_exp?(&1, now_fun))
    |> Joken.Config.add_claim("iat", fn -> nil end, &valid_iat?(&1, now_fun))
    |> Joken.Config.add_claim("purpose", fn -> nil end, &(&1 == @purpose_worlds_read))
  end

  defp aud_matches?(aud, expected) when is_binary(aud), do: aud == expected
  defp aud_matches?(aud, expected) when is_list(aud), do: expected in aud
  defp aud_matches?(_, _), do: false

  defp valid_exp?(exp, now_fun) when is_integer(exp), do: exp + @skew_seconds >= now_fun.()
  defp valid_exp?(_, _), do: false

  defp valid_iat?(iat, now_fun) when is_integer(iat), do: iat - @skew_seconds <= now_fun.()
  defp valid_iat?(_, _), do: false

  defp default_fetch(url) do
    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
