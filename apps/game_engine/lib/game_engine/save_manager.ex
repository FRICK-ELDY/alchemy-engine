defmodule GameEngine.SaveManager do
  require Logger

  @save_version 1
  @high_scores_max 10

  # HMAC 署名用の秘密鍵。
  # 将来的にはビルド時環境変数や設定ファイルから注入することを推奨する。
  @hmac_secret "alchemy-engine-save-secret-v1"

  # ── パス解決 ────────────────────────────────────────────────────────────

  defp save_dir do
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

  def save_session(world_ref) do
    try do
      snapshot = GameEngine.NifBridge.get_save_snapshot(world_ref)
      write_json(session_path(), snapshot_to_map(snapshot))
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # ── セッションロード ─────────────────────────────────────────────────────

  def load_session(world_ref) do
    case read_json(session_path()) do
      {:ok, data} ->
        try do
          snapshot = map_to_snapshot(data["state"])
          GameEngine.NifBridge.load_save_snapshot(world_ref, snapshot)
          :ok
        rescue
          e -> {:error, Exception.message(e)}
        end

      :not_found ->
        :no_save

      {:error, reason} ->
        {:error, reason}
    end
  end

  def has_save? do
    File.exists?(session_path())
  end

  # ── ハイスコア保存 ───────────────────────────────────────────────────────

  def save_high_score(score) when is_integer(score) and score >= 0 do
    try do
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
  end

  def save_high_score(_), do: {:error, :invalid_score}

  # ── ハイスコアロード ─────────────────────────────────────────────────────

  def load_high_scores do
    case read_json(high_scores_path()) do
      {:ok, %{"scores" => scores}} when is_list(scores) ->
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

    json = Jason.encode!(payload)
    hmac = compute_hmac(json)
    envelope = Jason.encode!(%{"payload" => payload, "hmac" => hmac})

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, envelope)
    :ok
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, raw} ->
        case Jason.decode(raw) do
          {:ok, %{"payload" => payload, "hmac" => stored_hmac}} ->
            json = Jason.encode!(payload)

            if verify_hmac(json, stored_hmac) do
              {:ok, payload}
            else
              Logger.warning("[SAVE] HMAC mismatch: #{path}")
              {:error, :tampered}
            end

          {:ok, _} ->
            {:error, :invalid_format}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, :file.format_error(reason)}
    end
  end

  # ── HMAC 計算・検証 ──────────────────────────────────────────────────────

  defp compute_hmac(json) do
    :crypto.mac(:hmac, :sha256, @hmac_secret, json) |> Base.encode64()
  end

  defp verify_hmac(json, stored_hmac) do
    expected = compute_hmac(json)
    # タイミング攻撃対策として定数時間比較を使用
    :crypto.hash_equals(Base.decode64!(expected), Base.decode64!(stored_hmac))
  rescue
    _ -> false
  end

  # ── SaveSnapshot ↔ map 変換 ──────────────────────────────────────────────

  defp snapshot_to_map(snapshot) do
    %{
      "player_hp" => snapshot.player_hp,
      "player_x" => snapshot.player_x,
      "player_y" => snapshot.player_y,
      "player_max_hp" => snapshot.player_max_hp,
      "elapsed_seconds" => snapshot.elapsed_seconds,
      "weapon_slots" =>
        Enum.map(snapshot.weapon_slots, fn ws ->
          %{"kind_id" => ws.kind_id, "level" => ws.level}
        end)
    }
  end

  defp map_to_snapshot(map) do
    weapon_slots =
      (map["weapon_slots"] || [])
      |> Enum.map(fn ws ->
        %{kind_id: ws["kind_id"], level: ws["level"]}
      end)

    %{
      player_hp: map["player_hp"],
      player_x: map["player_x"],
      player_y: map["player_y"],
      player_max_hp: map["player_max_hp"],
      elapsed_seconds: map["elapsed_seconds"],
      weapon_slots: weapon_slots
    }
  end
end
