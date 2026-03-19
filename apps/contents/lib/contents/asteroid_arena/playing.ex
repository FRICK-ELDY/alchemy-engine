defmodule Content.AsteroidArena.Playing do
  @moduledoc """
  AsteroidArena のプレイ中シーン。

  武器・ボス・レベルアップの概念を持たない。
  小惑星と UFO のスポーン、プレイヤー死亡判定のみを行う。

  Phase 5 移行: SpawnSystem ロジックを統合。NIF との境界を Object 層で整理。
  """
  @behaviour Contents.SceneBehaviour

  require Logger

  @asteroid_large 0
  @asteroid_medium 1
  @asteroid_small 2
  @ufo 3
  @max_enemies 500
  @item_gem 0

  @waves [
    {0, 4_000, 2},
    {30, 3_000, 3},
    {90, 2_000, 4},
    {180, 1_500, 5}
  ]

  @ufo_schedule [
    {60, 60_000},
    {120, 45_000},
    {180, 30_000}
  ]

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       exp: 0,
       last_ufo_spawn_ms: 0,
       last_spawn_ms: nil,
       player_hp: 100.0,
       player_max_hp: 100.0,
       invincible_until_ms: nil
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(context, state) do
    elapsed = context.elapsed
    player_hp = Map.get(state, :player_hp, 100.0)

    if player_hp <= 0.0 do
      Logger.info("[GAME OVER] Player HP reached 0 at #{div(elapsed, 1000)}s")
      {:transition, {:replace, Content.AsteroidArena.GameOver, %{}}, state}
    else
      last_spawn_ms = Map.get(state, :last_spawn_ms) || context.start_ms
      new_last_spawn = maybe_spawn(context.world_ref, elapsed, last_spawn_ms)

      new_last_ufo =
        maybe_spawn_ufo(context.world_ref, elapsed, state.last_ufo_spawn_ms)

      new_state = %{state | last_ufo_spawn_ms: new_last_ufo, last_spawn_ms: new_last_spawn}

      {:continue, new_state}
    end
  end

  # ── スポーン（SpawnSystem から統合）────────────────────────────────────

  def maybe_spawn(world_ref, elapsed_ms, last_spawn_ms) do
    elapsed_sec = elapsed_ms / 1000.0
    {interval_ms, count} = current_wave(elapsed_sec)

    if elapsed_ms - last_spawn_ms >= interval_ms do
      current = Core.get_enemy_count(world_ref)

      if current < @max_enemies do
        to_spawn = min(count, @max_enemies - current)
        Core.NifBridge.spawn_enemies(world_ref, @asteroid_large, to_spawn)
      end

      elapsed_ms
    else
      last_spawn_ms
    end
  end

  def maybe_spawn_ufo(world_ref, elapsed_ms, last_ufo_spawn_ms) do
    elapsed_sec = elapsed_ms / 1000.0

    case ufo_interval(elapsed_sec) do
      nil ->
        last_ufo_spawn_ms

      interval_ms ->
        if elapsed_ms - last_ufo_spawn_ms >= interval_ms do
          Core.NifBridge.spawn_enemies(world_ref, @ufo, 1)
          elapsed_ms
        else
          last_ufo_spawn_ms
        end
    end
  end

  defp current_wave(elapsed_sec) do
    fallback = {4_000, 2}

    @waves
    |> Enum.reverse()
    |> Enum.find(fn {start, _i, _c} -> elapsed_sec >= start end)
    |> case do
      nil -> fallback
      {_start, interval, count} -> {interval, count}
    end
  end

  defp ufo_interval(elapsed_sec) do
    case @ufo_schedule
         |> Enum.reverse()
         |> Enum.find(fn {start, _i} -> elapsed_sec >= start end) do
      nil -> nil
      {_start, interval} -> interval
    end
  end

  # ── 分裂・報酬（SplitComponent から統合）────────────────────────────────

  @doc """
  敵撃破時の分裂処理とアイテムドロップ。handle_enemy_killed コールバック用。
  """
  def handle_split_and_drop(world_ref, kind_id, x, y) do
    handle_split(world_ref, kind_id, x, y)

    exp = Content.AsteroidArena.enemy_exp_reward(kind_id)

    if exp > 0 do
      Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
    end

    :ok
  end

  defp handle_split(world_ref, kind_id, x, y) do
    case kind_id do
      @asteroid_large ->
        spawn_split(world_ref, @asteroid_medium, x, y, 2)

      @asteroid_medium ->
        spawn_split(world_ref, @asteroid_small, x, y, 2)

      _ ->
        :ok
    end
  end

  defp spawn_split(world_ref, kind_id, x, y, count) do
    positions =
      for i <- 0..(count - 1) do
        angle = i * :math.pi() * 2.0 / count + (:rand.uniform() - 0.5) * 0.5
        dist = 40.0 + :rand.uniform() * 20.0
        {x + :math.cos(angle) * dist, y + :math.sin(angle) * dist}
      end

    Core.NifBridge.spawn_enemies_at(world_ref, kind_id, positions)
  end
end
