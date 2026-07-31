defmodule Network.AuthVerifier do
  @moduledoc """
  alchemy-auth 発行の Bearer JWT を JWKS 公開鍵で検証する。

  契約: `auth/docs/jwt-jwks-engine-contract.md`
  - RS256 / kid / iss / aud / exp / iat / sub / jti / status
  - clock skew ±60 秒
  - jti 失効 DB は参照しない（外部 verifier）
  - JWKS キャッシュ + kid miss 時再取得 + 定期更新

  `POST /api/room_token` は `config :network, :auth_required` が true のときのみ
  本モジュールの検証を必須とする（`AUTH_REQUIRED`）。
  """

  use GenServer
  require Logger

  @skew_seconds 60
  @cache_ttl_ms :timer.minutes(10)
  @uuid_re ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

  # ── Public API ───────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Bearer JWT を検証し claims を返す。

  ## 戻り値
  - `{:ok, claims}`
  - `{:error, reason}` — `:missing_kid` / `:invalid_alg` / `:unknown_kid` /
    `:inactive_status` / `:jwks_unavailable` / `{:token_validation_failed, _}` 等
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:verify, token})
  catch
    :exit, {:noproc, _} -> {:error, :verifier_not_running}
  end

  @doc false
  @spec put_jwks(map()) :: :ok
  def put_jwks(%{"keys" => _} = jwks) do
    GenServer.call(__MODULE__, {:put_jwks, jwks})
  end

  @doc false
  @spec refresh_jwks() :: :ok | {:error, term()}
  def refresh_jwks do
    GenServer.call(__MODULE__, :refresh_jwks)
  end

  # ── GenServer ────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      jwks_url: Keyword.get(opts, :jwks_url) || configured_jwks_url(),
      issuer: Keyword.get(opts, :issuer) || configured_issuer(),
      audience: Keyword.get(opts, :audience) || configured_audience(),
      skew_seconds: Keyword.get(opts, :skew_seconds, @skew_seconds),
      cache_ttl_ms: Keyword.get(opts, :cache_ttl_ms, @cache_ttl_ms),
      fetch_fun: Keyword.get(opts, :fetch_fun, &default_fetch/1),
      signers_by_kid: %{},
      fetched_at: nil
    }

    cond do
      jwks = Keyword.get(opts, :jwks) || Application.get_env(:network, :auth_jwks_static) ->
        {:ok, apply_jwks(state, jwks), {:continue, :schedule_refresh}}

      is_binary(state.jwks_url) and state.jwks_url != "" ->
        {:ok, state, {:continue, :initial_fetch}}

      true ->
        {:ok, state}
    end
  end

  @impl true
  def handle_continue(:initial_fetch, state) do
    case do_fetch(state) do
      {:ok, new_state} ->
        {:noreply, new_state, {:continue, :schedule_refresh}}

      {:error, reason} ->
        Logger.warning("[AuthVerifier] initial JWKS fetch failed: #{inspect(reason)}")
        {:noreply, schedule_refresh(state)}
    end
  end

  def handle_continue(:schedule_refresh, state) do
    {:noreply, schedule_refresh(state)}
  end

  @impl true
  def handle_info(:refresh_jwks, state) do
    new_state =
      case do_fetch(state) do
        {:ok, s} ->
          s

        {:error, reason} ->
          Logger.warning("[AuthVerifier] JWKS refresh failed: #{inspect(reason)}")
          state
      end

    {:noreply, schedule_refresh(new_state)}
  end

  @impl true
  def handle_call({:verify, token}, _from, state) do
    {reply, new_state} = do_verify(token, state, _retried? = false)
    {:reply, reply, new_state}
  end

  def handle_call({:put_jwks, jwks}, _from, state) do
    {:reply, :ok, apply_jwks(state, jwks)}
  end

  def handle_call(:refresh_jwks, _from, state) do
    case do_fetch(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # ── Verify ───────────────────────────────────────────────────────

  defp do_verify(token, state, retried?) do
    with {:ok, header} <- peek_header(token),
         :ok <- validate_alg(header),
         {:ok, kid} <- fetch_kid(header),
         {:ok, signer, state} <- resolve_signer(kid, state, retried?),
         {:ok, claims} <- verify_signature_and_claims(token, signer, state),
         :ok <- ensure_active_status(claims) do
      {{:ok, claims}, state}
    else
      {:error, :unknown_kid, state} ->
        cond do
          retried? ->
            {{:error, :unknown_kid}, state}

          can_fetch?(state) ->
            case do_fetch(state) do
              {:ok, refreshed} -> do_verify(token, refreshed, true)
              {:error, reason} -> {{:error, {:jwks_unavailable, reason}}, state}
            end

          true ->
            {{:error, :unknown_kid}, state}
        end

      {:error, reason} ->
        {{:error, reason}, state}

      {:error, reason, state} ->
        {{:error, reason}, state}
    end
  rescue
    error ->
      {{:error, {:token_verify_exception, error}}, state}
  end

  defp peek_header(token) do
    case Joken.peek_header(token) do
      {:ok, header} when is_map(header) -> {:ok, header}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_alg(%{"alg" => "RS256"}), do: :ok
  defp validate_alg(%{"alg" => _}), do: {:error, :invalid_alg}
  defp validate_alg(_), do: {:error, :invalid_alg}

  defp fetch_kid(%{"kid" => kid}) when is_binary(kid) and kid != "", do: {:ok, kid}
  defp fetch_kid(_), do: {:error, :missing_kid}

  defp resolve_signer(kid, state, _retried?) do
    case Map.fetch(state.signers_by_kid, kid) do
      {:ok, signer} -> {:ok, signer, state}
      :error -> {:error, :unknown_kid, state}
    end
  end

  defp verify_signature_and_claims(token, signer, state) do
    case Joken.verify_and_validate(token_config(state), token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, {:token_validation_failed, reason}}
    end
  end

  defp ensure_active_status(%{"status" => "active"}), do: :ok
  defp ensure_active_status(%{"status" => _}), do: {:error, :inactive_status}
  defp ensure_active_status(_), do: {:error, :inactive_status}

  defp token_config(state) do
    skew = state.skew_seconds
    issuer = state.issuer
    audience = state.audience
    now_fun = fn -> System.system_time(:second) end

    Joken.Config.default_claims(skip: [:iss, :aud, :exp, :iat, :nbf, :jti])
    |> Joken.Config.add_claim("iss", fn -> nil end, &(&1 == issuer))
    |> Joken.Config.add_claim("aud", fn -> nil end, &aud_matches?(&1, audience))
    |> Joken.Config.add_claim("exp", fn -> nil end, &valid_exp?(&1, now_fun, skew))
    |> Joken.Config.add_claim("iat", fn -> nil end, &valid_iat?(&1, now_fun, skew))
    |> Joken.Config.add_claim("sub", fn -> nil end, &valid_uuid?/1)
    |> Joken.Config.add_claim("jti", fn -> nil end, &valid_uuid?/1)
    |> Joken.Config.add_claim("status", fn -> nil end, &valid_status?/1)
  end

  defp aud_matches?(aud, expected) when is_binary(aud), do: aud == expected
  defp aud_matches?(aud, expected) when is_list(aud), do: expected in aud
  defp aud_matches?(_, _), do: false

  defp valid_exp?(exp, now_fun, skew) when is_integer(exp), do: now_fun.() <= exp + skew
  defp valid_exp?(_, _, _), do: false

  defp valid_iat?(iat, now_fun, skew) when is_integer(iat), do: now_fun.() >= iat - skew
  defp valid_iat?(_, _, _), do: false

  defp valid_uuid?(value) when is_binary(value), do: Regex.match?(@uuid_re, value)
  defp valid_uuid?(_), do: false

  defp valid_status?(value) when value in ["active", "suspended", "deleted"], do: true
  defp valid_status?(_), do: false

  # ── JWKS ─────────────────────────────────────────────────────────

  defp do_fetch(%{jwks_url: url} = state) when is_binary(url) and url != "" do
    case state.fetch_fun.(url) do
      {:ok, %{"keys" => keys} = jwks} when is_list(keys) ->
        {:ok, apply_jwks(state, jwks)}

      {:ok, other} ->
        {:error, {:invalid_jwks, other}}

      {:error, _} = err ->
        err
    end
  end

  defp do_fetch(_state), do: {:error, :jwks_url_not_configured}

  defp can_fetch?(%{jwks_url: url}) when is_binary(url) and url != "", do: true
  defp can_fetch?(_), do: false

  defp apply_jwks(state, %{"keys" => keys}) when is_list(keys) do
    signers =
      keys
      |> Enum.map(&jwk_to_signer/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    %{state | signers_by_kid: signers, fetched_at: System.monotonic_time(:millisecond)}
  end

  defp jwk_to_signer(%{"kty" => "RSA", "kid" => kid} = jwk)
       when is_binary(kid) and kid != "" do
    try do
      jose_jwk = JOSE.JWK.from_map(jwk)
      {_type, pem} = JOSE.JWK.to_pem(jose_jwk)
      {kid, Joken.Signer.create("RS256", %{"pem" => pem}, %{"kid" => kid})}
    rescue
      error ->
        Logger.warning("[AuthVerifier] skip invalid JWK kid=#{kid}: #{inspect(error)}")
        nil
    end
  end

  defp jwk_to_signer(_), do: nil

  defp schedule_refresh(%{cache_ttl_ms: ttl} = state) when is_integer(ttl) and ttl > 0 do
    Process.send_after(self(), :refresh_jwks, ttl)
    state
  end

  defp schedule_refresh(state), do: state

  defp default_fetch(url) do
    case Req.get(url, decode_body: true, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp configured_jwks_url do
    case Application.get_env(:network, :auth_jwks_url) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        case Application.get_env(:network, :auth_base_url) do
          base when is_binary(base) and base != "" ->
            String.trim_trailing(base, "/") <> "/.well-known/jwks.json"

          _ ->
            nil
        end
    end
  end

  defp configured_issuer do
    Application.get_env(:network, :jwt_issuer, "alchemy-auth")
  end

  defp configured_audience do
    Application.get_env(:network, :jwt_audience, "alchemy-platform")
  end
end
