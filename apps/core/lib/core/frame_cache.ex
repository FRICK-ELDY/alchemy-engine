defmodule Core.FrameCache do
  @moduledoc """
  ルーム別のフレームスナップショットを ETS に書き込む。

  キーは `room_id`。値のスキーマ（enemy_count 等）は監視用途の現状契約で、
  コンテンツ語彙の分離は別タスクとする。
  """

  @table :frame_cache

  @doc """
  名前付き ETS テーブルを用意する。既に存在する場合は何もしない（冪等）。

  複数ルーム起動時の同時 `init/0` に備え、`:ets.new/2` の競合は
  `ArgumentError` を捕捉して無視する。
  """
  def init do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
          :ok
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end

  def put(
        room_id,
        enemy_count,
        bullet_count,
        physics_ms,
        hud_data,
        render_type \\ :playing,
        high_scores \\ nil
      ) do
    base = %{
      enemy_count: enemy_count,
      bullet_count: bullet_count,
      physics_ms: physics_ms,
      hud_data: hud_data,
      render_type: render_type,
      updated_at: System.monotonic_time(:millisecond)
    }

    data = if high_scores, do: Map.put(base, :high_scores, high_scores), else: base
    true = :ets.insert(@table, {room_id, data})
    :ok
  end

  def get(room_id) do
    case :ets.lookup(@table, room_id) do
      [{^room_id, data}] -> {:ok, data}
      [] -> :empty
    end
  rescue
    ArgumentError -> :empty
  end

  @doc "ルームのスナップショットを削除する（冪等）。"
  def delete(room_id) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete(@table, room_id)
        :ok
    end
  end

  @doc "全ルームの `{room_id, snapshot}` リストを返す。"
  def list do
    case :ets.whereis(@table) do
      :undefined -> []
      _tid -> :ets.tab2list(@table)
    end
  end
end
