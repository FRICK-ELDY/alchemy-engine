defmodule Core.SaveManager do
  @moduledoc """
  セッションデータおよびハイスコアの永続化を担当するモジュール。
  HMAC 署名付き JSON ファイルへの読み書きを行う。
  """

  require Logger

  @save_version 1
  @high_scores_max 10

  # ── パス解決 ────────────────────────────────────────────────────────────
  # テスト時は config :core, :save_dir で一時ディレクトリを指定する
  defp save_dir do
    case Application.get_env(:core, :save_dir) do
      nil -> default_save_dir()
      dir -> dir
    end
  end

  defp default_save_dir do
    base =
      case :os.type() do
        {:win32, _} ->
          System.get_env("APPDATA") || Path.expand("~")

        {:unix, :darwin} ->
          Path.expand("~/Library/Application Support")

        {:unix, _} ->
          System.get_env("XDG_DATA_HOME") || Path.expand("~/.local/share")
      end

    Path.join([base, "AlchemyEngine", "saves"])
  end

  defp session_path, do: Path.join(save_dir(), "session.json")
  defp high_scores_path, do: Path.join(save_dir(), "high_scores.json")

  # ── セッション保存 ───────────────────────────────────────────────────────
  #
  # weapon_slots はコンテンツ層 SSoT。opts[:weapon_slots] で渡す。
  def save_session(world_ref, opts \\ []) do
    snapshot = nif_bridge().get_save_snapshot(world_ref)
    weapon_slots = Keyword.get(opts, :weapon_slots, [])
    state_map = snapshot_to_map(snapshot, weapon_slots)
    write_json(session_path(), state_map)
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ── セッションロード ─────────────────────────────────────────────────────
  #
  # 成功時は {:ok, state_map} を返す。state_map の "weapon_slots" を
  # コンテンツの weapon_slots_to_levels/1 で weapon_levels に変換し、
  # シーン replace の initial_state に渡す。
  def load_session(world_ref) do
    case read_json(session_path()) do
      {:ok, data} -> do_load_session(world_ref, data)
      :not_found -> :no_save
      {:error, reason} -> {:error, reason}
    end
  end

  # read_json はエンベロープをデコードした payload を返す。
  # payload は %{"version" => _, "saved_at" => _, "state" => 実データ}（JSON 由来で文字列キー）。
  # セッションの実データは data["state"] に格納されている。
  defp do_load_session(world_ref, data) do
    state = data["state"] || %{}
    rust_snapshot = map_to_rust_snapshot(state)
    nif_bridge().load_save_snapshot(world_ref, rust_snapshot)
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  def has_save? do
    File.exists?(session_path())
  end

  # ── ハイスコア保存 ───────────────────────────────────────────────────────

  def save_high_score(score) when is_integer(score) and score >= 0 do
    current = load_high_scores()

    new_list =
      [score | current]
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.take(@high_scores_max)

    write_json(high_scores_path(), %{"scores" => new_list})
  rescue
    e -> {:error, Exception.message(e)}
  end

  def save_high_score(_), do: {:error, :invalid_score}

  # ── ハイスコアロード ─────────────────────────────────────────────────────
  # read_json の戻り値は JSON 由来のためキーはすべて文字列。
  # 現行: %{"version" => _, "saved_at" => _, "state" => %{"scores" => [...]}}
  # 旧式: %{"scores" => [...]}（エンベロープなし）

  def load_high_scores do
    case read_json(high_scores_path()) do
      # 現行フォーマット: エンベロープ内 state に scores を格納
      {:ok, %{"state" => %{"scores" => scores}}} when is_list(scores) ->
        scores

      # 旧フォーマット: scores が直下にある場合（後方互換）
      {:ok, %{"scores" => scores}} when is_list(scores) ->
        Logger.info("[SAVE] Loaded high scores from legacy format (no envelope)")
        scores

      :not_found ->
        []

      {:error, reason} ->
        Logger.warning("[SAVE] Failed to load high scores: #{inspect(reason)}")
        []
    end
  end

  def best_score do
    case load_high_scores() do
      [best | _] -> best
      [] -> nil
    end
  end

  # ── JSON 読み書き（HMAC 署名付き）───────────────────────────────────────

  defp write_json(path, data) do
    payload = %{
      "version" => @save_version,
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "state" => data
    }

    # HMAC はエンコード済み JSON 文字列に対して計算し、
    # その文字列をそのままエンベロープに格納する。
    # マップを再エンコードするとキー順序が変わり HMAC 不一致になるため。
    json = Jason.encode!(payload)
    hmac = compute_hmac(json)
    envelope = Jason.encode!(%{"payload" => json, "hmac" => hmac})

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, envelope)
    :ok
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, raw} -> decode_envelope(raw, path)
      {:error, :enoent} -> :not_found
      {:error, reason} -> {:error, :file.format_error(reason)}
    end
  end

  defp decode_envelope(raw, path) do
    case Jason.decode(raw) do
      {:ok, %{"payload" => json, "hmac" => stored_hmac}} when is_binary(json) ->
        verify_and_decode(json, stored_hmac, path)

      {:ok, _} ->
        {:error, :invalid_format}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_and_decode(json, stored_hmac, path) do
    if verify_hmac(json, stored_hmac) do
      case Jason.decode(json) do
        {:ok, payload} -> {:ok, payload}
        {:error, reason} -> {:error, reason}
      end
    else
      Logger.warning("[SAVE] HMAC mismatch: #{path}")
      {:error, :tampered}
    end
  end

  # ── HMAC 計算・検証 ──────────────────────────────────────────────────────

  defp hmac_secret do
    Application.get_env(:core, :save_hmac_secret, "alchemy-engine-save-secret-v1")
  end

  defp compute_hmac(json) do
    :crypto.mac(:hmac, :sha256, hmac_secret(), json) |> Base.encode64()
  end

  defp verify_hmac(json, stored_hmac) do
    expected_binary = :crypto.mac(:hmac, :sha256, hmac_secret(), json)

    case Base.decode64(stored_hmac) do
      {:ok, stored_binary} ->
        # タイミング攻撃対策として定数時間比較を使用
        :crypto.hash_equals(expected_binary, stored_binary)

      :error ->
        false
    end
  end

  # ── SaveSnapshot ↔ map 変換 ──────────────────────────────────────────────

  defp snapshot_to_map(snapshot, weapon_slots) do
    base = %{
      "player_hp" => snapshot.player_hp,
      "player_x" => snapshot.player_x,
      "player_y" => snapshot.player_y,
      "player_max_hp" => snapshot.player_max_hp,
      "elapsed_seconds" => snapshot.elapsed_seconds
    }

    if weapon_slots == [] do
      Map.put(base, "weapon_slots", [])
    else
      slots =
        Enum.map(weapon_slots, fn ws ->
          %{"kind_id" => ws[:kind_id] || ws["kind_id"], "level" => ws[:level] || ws["level"]}
        end)

      Map.put(base, "weapon_slots", slots)
    end
  end

  defp nif_bridge do
    Application.get_env(:core, :nif_bridge, Core.NifBridge)
  end

  defp map_to_rust_snapshot(map) do
    # 必須キーの検証（旧セーブ・破損データ対策）。nil の場合はデフォルトを使用し、NIF に nil を渡さない。
    safe_float = fn key, default ->
      case map[key] do
        nil -> default
        n when is_number(n) -> n
        _ -> raise ArgumentError, "Invalid save data: #{key} must be a number"
      end
    end

    %{
      player_hp: safe_float.("player_hp", 0.0),
      player_x: safe_float.("player_x", 0.0),
      player_y: safe_float.("player_y", 0.0),
      player_max_hp: safe_float.("player_max_hp", 100.0),
      elapsed_seconds: safe_float.("elapsed_seconds", 0.0)
    }
  end
end
