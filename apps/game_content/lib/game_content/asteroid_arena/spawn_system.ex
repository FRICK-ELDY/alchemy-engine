defmodule GameContent.AsteroidArena.SpawnSystem do
  @moduledoc """
  AsteroidArena のウェーブスポーンシステム。

  経過時間に応じて小惑星・UFO をスポーンする。
  小惑星は on_entity_removed イベントで分裂処理を行う。
  """

  # ── 種別 ID ────────────────────────────────────────────────────────
  @asteroid_large 0
  @asteroid_medium 1
  @asteroid_small 2
  @ufo 3

  # ── スポーン上限 ───────────────────────────────────────────────────
  @max_enemies 500

  # ── ウェーブ定義 {開始秒, スポーン間隔ms, 1回の数} ────────────────
  @waves [
    {0, 4_000, 2},
    {30, 3_000, 3},
    {90, 2_000, 4},
    {180, 1_500, 5}
  ]

  # ── UFO 出現スケジュール {開始秒, 出現間隔ms} ─────────────────────
  @ufo_schedule [
    {60, 60_000},
    {120, 45_000},
    {180, 30_000}
  ]

  # ── EXP 報酬（Elixir SSoT）────────────────────────────────────────
  @exp_rewards %{
    @asteroid_large => 20,
    @asteroid_medium => 10,
    @asteroid_small => 5,
    @ufo => 50
  }

  @doc "経過時間に応じて小惑星をスポーンする。戻り値は更新後の last_spawn_ms"
  def maybe_spawn(world_ref, elapsed_ms, last_spawn_ms) do
    elapsed_sec = elapsed_ms / 1000.0
    {interval_ms, count} = current_wave(elapsed_sec)

    if elapsed_ms - last_spawn_ms >= interval_ms do
      current = GameEngine.get_enemy_count(world_ref)

      if current < @max_enemies do
        to_spawn = min(count, @max_enemies - current)
        GameEngine.NifBridge.spawn_enemies(world_ref, @asteroid_large, to_spawn)
      end

      elapsed_ms
    else
      last_spawn_ms
    end
  end

  @doc "経過時間に応じて UFO をスポーンする。戻り値は更新後の last_ufo_spawn_ms"
  def maybe_spawn_ufo(world_ref, elapsed_ms, last_ufo_spawn_ms) do
    elapsed_sec = elapsed_ms / 1000.0

    case ufo_interval(elapsed_sec) do
      nil ->
        last_ufo_spawn_ms

      interval_ms ->
        if elapsed_ms - last_ufo_spawn_ms >= interval_ms do
          GameEngine.NifBridge.spawn_enemies(world_ref, @ufo, 1)
          elapsed_ms
        else
          last_ufo_spawn_ms
        end
    end
  end

  @doc """
  小惑星撃破時の分裂処理。

  - Large → Medium × 2
  - Medium → Small × 2
  - Small / UFO → 消滅のみ
  """
  def handle_split(world_ref, kind_id, x, y) do
    case kind_id do
      @asteroid_large ->
        spawn_split(world_ref, @asteroid_medium, x, y, 2)

      @asteroid_medium ->
        spawn_split(world_ref, @asteroid_small, x, y, 2)

      _ ->
        :ok
    end
  end

  @doc "敵種別 ID の EXP 報酬を返す"
  def exp_reward(kind_id), do: Map.get(@exp_rewards, kind_id, 0)

  @doc "スコア = EXP × 2"
  def score_from_exp(exp), do: exp * 2

  @doc "ウェーブラベルを返す（ログ・HUD 用）"
  def wave_label(elapsed_sec) do
    cond do
      elapsed_sec < 30 -> "Wave 1 - Asteroids"
      elapsed_sec < 90 -> "Wave 2 - Denser"
      elapsed_sec < 180 -> "Wave 3 - UFOs Appear"
      true -> "Wave 4 - Chaos"
    end
  end

  # ── プライベート ────────────────────────────────────────────────────

  defp current_wave(elapsed_sec) do
    # Enum.find_last/2 は Elixir 1.12 以降で追加されているが、
    # 使用環境（Elixir 1.19.5 + OTP 28）で undefined エラーが発生するため
    # Enum.reverse/1 + Enum.find/2 で代替している（条件一致時点で走査を停止）。
    @waves
    |> Enum.reverse()
    |> Enum.find(fn {start, _i, _c} -> elapsed_sec >= start end)
    |> then(fn {_start, interval, count} -> {interval, count} end)
  end

  defp ufo_interval(elapsed_sec) do
    # 同上: Enum.find_last/2 の代替
    case @ufo_schedule
         |> Enum.reverse()
         |> Enum.find(fn {start, _i} -> elapsed_sec >= start end) do
      nil -> nil
      {_start, interval} -> interval
    end
  end

  defp spawn_split(world_ref, kind_id, x, y, count) do
    positions =
      for i <- 0..(count - 1) do
        angle = i * :math.pi() * 2.0 / count + (:rand.uniform() - 0.5) * 0.5
        dist = 40.0 + :rand.uniform() * 20.0
        {x + :math.cos(angle) * dist, y + :math.sin(angle) * dist}
      end

    GameEngine.NifBridge.spawn_enemies_at(world_ref, kind_id, positions)
  end
end
