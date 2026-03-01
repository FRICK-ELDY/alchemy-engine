defmodule GameEngine.FrameCache do
  @moduledoc """
  フレームごとのゲーム状態を ETS に書き込む。
  """

  @table :frame_cache

  def init do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  def put(
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
    :ets.insert(@table, {:snapshot, data})
  end

  def get do
    case :ets.lookup(@table, :snapshot) do
      [{:snapshot, data}] -> {:ok, data}
      [] -> :empty
    end
  rescue
    ArgumentError -> :empty
  end
end
