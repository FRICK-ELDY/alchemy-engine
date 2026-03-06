defmodule Core.FormulaStore do
  @moduledoc """
  ProtoFlux 風の変数ストレージ。Phase 4 で導入。

  ## スコープ
  - `:synced` — セッション全体で共有、ネットワーク同期（DataModelStore 相当）
  - `:local` — クライアント内グローバル、非同期（Store 相当）
  - `:context` — 評価コンテキスト内のみ有効（Local 相当、呼び出し側で map を渡す）

  ## 責務
  - Elixir が Store の定義・永続化を担当
  - Rust はキー＋値の受け渡しのみ

  ## 設定（config :core, :formula_store_broadcast）
  synced 更新時のブロードキャスト用。未設定または `nil` のときはブロードキャストしない。
  - `{Mod, Fun, []}` — `apply(Mod, Fun, [room_id, {:formula_store_synced, key, value}])` を呼ぶ。
    `Network.Distributed.broadcast/2` 互換の 2 引数関数を指定すること。
  - `fun`（2 引数関数）— `fun.(room_id, {:formula_store_synced, key, value})` を呼ぶ。
  - core 単体利用（network 未ロード）の場合は必ず `nil` を設定すること。

  ## 使い方

      # 実行前に store_values を構築
      synced_keys = ["score", "wave"]
      local_keys = ["preference"]
      store_values =
        FormulaStore.merge_for_run(room_id, synced_keys, local_keys, context_map)

      {:ok, {outputs, store_list}} = FormulaGraph.run(graph, inputs, store_values)

      # 更新を適用（synced は broadcast も行う）
      FormulaStore.apply_updates(room_id, store_list, synced_keys, local_keys)
  """

  @synced_table :formula_store_synced

  @doc """
  ETS テーブルを初期化する。初回利用時に自動で呼ばれる。

  既にテーブルが存在する場合は何もしない。
  """
  def init do
    if :ets.whereis(@synced_table) == :undefined do
      :ets.new(@synced_table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc """
  synced スコープで値を読む。
  """
  @spec read_synced(term(), String.t(), term()) :: term()
  def read_synced(room_id, key, default) do
    ensure_init()

    case :ets.lookup(@synced_table, {room_id, key}) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc """
  synced スコープで値を書き込む。書き込み後に Network.broadcast で他クライアントへ通知する。
  """
  @spec write_synced(term(), String.t(), term()) :: :ok
  def write_synced(room_id, key, value) do
    ensure_init()
    :ets.insert(@synced_table, {{room_id, key}, value})
    broadcast_synced(room_id, key, value)
    :ok
  end

  @doc """
  local スコープで値を読む。

  LocalBackend が起動していない場合は default を返す。
  """
  @spec read_local(String.t(), term()) :: term()
  def read_local(key, default) do
    case safe_local_get(key) do
      {:ok, value} -> value
      _ -> default
    end
  end

  @doc """
  local スコープで値を書き込む。ネットワーク同期は行わない。

  LocalBackend が起動していない場合は何もしない。
  """
  @spec write_local(String.t(), term()) :: :ok
  def write_local(key, value) do
    safe_local_put(key, value)
    :ok
  end

  @doc """
  Formula.run/3 に渡す store_values を構築する。

  synced_keys, local_keys に含まれるキーを各ストアから読み、context_map とマージする。
  """
  @spec merge_for_run(term(), [String.t()], [String.t()], map()) :: map()
  def merge_for_run(room_id, synced_keys, local_keys, context_map \\ %{}) do
    synced =
      Enum.reduce(synced_keys, %{}, fn key, acc ->
        case read_synced(room_id, key, nil) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    local =
      Enum.reduce(local_keys, %{}, fn key, acc ->
        case read_local(key, nil) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    context_map
    |> Map.merge(local)
    |> Map.merge(synced)
  end

  @doc """
  Formula.run/3 の戻り値 store_list を適用する。

  synced_keys に含まれるキーは write_synced（broadcast あり）、
  local_keys に含まれるキーは write_local で永続化する。
  その他のキーは無視する。
  """
  @spec apply_updates(term(), [{String.t(), term()}], [String.t()], [String.t()]) :: :ok
  def apply_updates(room_id, store_list, synced_keys, local_keys) do
    synced_set = MapSet.new(synced_keys)
    local_set = MapSet.new(local_keys)

    Enum.each(store_list, fn {key, value} ->
      cond do
        MapSet.member?(synced_set, key) -> write_synced(room_id, key, value)
        MapSet.member?(local_set, key) -> write_local(key, value)
        true -> :ok
      end
    end)

    :ok
  end

  @doc """
  ネットワーク経由で受け取った synced 更新を適用する。

  GameEvents が `{:network_event, from_room, {:formula_store_synced, key, value}}` を受信したときに呼ぶ。
  受信側ルームの store を更新する。key は to_string/1 で文字列に正規化される。
  """
  @spec apply_synced_from_network(term(), String.t() | atom(), term()) :: :ok
  def apply_synced_from_network(room_id, key, value) do
    ensure_init()
    key_str = to_string(key)
    :ets.insert(@synced_table, {{room_id, key_str}, value})
    :ok
  end

  defp ensure_init do
    init()
  end

  defp safe_local_get(key) do
    if Process.whereis(Core.FormulaStore.LocalBackend) do
      Core.FormulaStore.LocalBackend.get(key)
    else
      :error
    end
  end

  defp safe_local_put(key, value) do
    if Process.whereis(Core.FormulaStore.LocalBackend) do
      Core.FormulaStore.LocalBackend.put(key, value)
    end

    :ok
  end

  defp broadcast_synced(room_id, key, value) do
    event = {:formula_store_synced, key, value}

    result =
      case Application.get_env(:core, :formula_store_broadcast) do
        {mod, fun, []} when is_atom(mod) and is_atom(fun) ->
          apply(mod, fun, [room_id, event])

        fun when is_function(fun, 2) ->
          fun.(room_id, event)

        _ ->
          :ok
      end

    if result == {:error, :room_not_found} do
      require Logger

      Logger.warning(
        "[FormulaStore] broadcast failed: room_not_found room_id=#{inspect(room_id)}"
      )
    end

    :ok
  end
end
