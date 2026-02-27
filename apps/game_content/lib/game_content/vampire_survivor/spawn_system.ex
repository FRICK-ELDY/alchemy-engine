defmodule GameContent.VampireSurvivor.SpawnSystem do
  @moduledoc """
  ウェーブベース敵スポーンシステム（ヴァンサバ固有）。
  """

  @max_enemies 10_000

  @waves [
    { 0, 300, 20},
    {10, 220, 30},
    {20, 170, 45},
    {40, 130, 60},
    {60, 110, 75},
  ]

  @elite_start_sec 45
  @elite_hp_multiplier 3.0

  def maybe_spawn(world_ref, elapsed_ms, last_spawn_ms) do
    elapsed_sec = elapsed_ms / 1000.0
    {interval_ms, count} = current_wave(elapsed_sec)

    if elapsed_ms - last_spawn_ms >= interval_ms do
      current = GameEngine.get_enemy_count(world_ref)

      if current < @max_enemies do
        to_spawn = min(count, @max_enemies - current)
        kind = enemy_kind_for_wave(elapsed_sec)

        if elapsed_sec >= @elite_start_sec do
          spawn_with_elites(world_ref, kind, to_spawn)
        else
          GameEngine.spawn_enemies(world_ref, kind, to_spawn)
        end
      end

      elapsed_ms
    else
      last_spawn_ms
    end
  end

  def spawn_with_elites(world_ref, kind, count) do
    elite_count  = max(1, div(count * 3, 10))
    normal_count = count - elite_count

    if normal_count > 0, do: GameEngine.spawn_enemies(world_ref, kind, normal_count)
    if elite_count > 0,  do: GameEngine.spawn_elite_enemy(world_ref, kind, elite_count, @elite_hp_multiplier)
  end

  def current_wave(elapsed_sec) do
    @waves
    |> Enum.filter(fn {start, _i, _c} -> elapsed_sec >= start end)
    |> List.last({0, 800, 20})
    |> then(fn {_start, interval, count} -> {interval, count} end)
  end

  def enemy_kind_for_wave(elapsed_sec) do
    cond do
      elapsed_sec < 10  -> Enum.random([:slime, :bat])
      elapsed_sec < 20  -> Enum.random([:slime, :bat, :skeleton])
      elapsed_sec < 40  -> Enum.random([:slime, :bat, :skeleton, :ghost])
      true              -> Enum.random([:slime, :bat, :skeleton, :ghost, :golem])
    end
  end

  def wave_label(elapsed_sec) do
    cond do
      elapsed_sec < 10  -> "Wave 1 - High Spawn Start"
      elapsed_sec < 20  -> "Wave 2 - Skeleton Added"
      elapsed_sec < 40  -> "Wave 3 - Ghost Added"
      elapsed_sec < 60  -> "Wave 4 - Golem Added"
      true              -> "Wave 5 - ELITE (HP x3)"
    end
  end
end
