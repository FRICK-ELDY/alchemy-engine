defmodule GameContent.VampireSurvivorRule do
  @moduledoc """
  ヴァンパイアサバイバーの RuleBehaviour 実装。

  シーン構成・ゲームロジック・スポーン/ボス/レベルアップの制御を定義する。
  `VampireSurvivorWorld` と組み合わせて使用する。
  """
  @behaviour GameEngine.RuleBehaviour

  @impl GameEngine.RuleBehaviour
  def render_type, do: :playing

  @impl GameEngine.RuleBehaviour
  def initial_scenes do
    [
      %{module: GameContent.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  @impl GameEngine.RuleBehaviour
  def physics_scenes do
    [GameContent.VampireSurvivor.Scenes.Playing]
  end

  @impl GameEngine.RuleBehaviour
  def title, do: "Vampire Survivor"

  @impl GameEngine.RuleBehaviour
  def version, do: "0.1.0"

  @impl GameEngine.RuleBehaviour
  def context_defaults, do: %{}

  @impl GameEngine.RuleBehaviour
  def playing_scene, do: GameContent.VampireSurvivor.Scenes.Playing

  @impl GameEngine.RuleBehaviour
  def generate_weapon_choices(weapon_levels) do
    GameContent.VampireSurvivor.LevelSystem.generate_weapon_choices(weapon_levels)
  end

  @impl GameEngine.RuleBehaviour
  def apply_level_up(scene_state, choices) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up(scene_state, choices)
  end

  @impl GameEngine.RuleBehaviour
  def apply_weapon_selected(scene_state, weapon) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_weapon_selected(scene_state, weapon)
  end

  @impl GameEngine.RuleBehaviour
  def apply_level_up_skipped(scene_state) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up_skipped(scene_state)
  end

  @impl GameEngine.RuleBehaviour
  def game_over_scene, do: GameContent.VampireSurvivor.Scenes.GameOver

  @impl GameEngine.RuleBehaviour
  def level_up_scene, do: GameContent.VampireSurvivor.Scenes.LevelUp

  @impl GameEngine.RuleBehaviour
  def boss_alert_scene, do: GameContent.VampireSurvivor.Scenes.BossAlert

  @impl GameEngine.RuleBehaviour
  def wave_label(elapsed_sec) do
    GameContent.VampireSurvivor.SpawnSystem.wave_label(elapsed_sec)
  end

  # Phase 3-B: 敵撃破時のアイテムドロップ処理
  @impl GameEngine.RuleBehaviour
  def on_entity_removed(world_ref, kind_id, x, y) do
    roll = :rand.uniform(100)
    cond do
      roll <= 2  -> GameEngine.NifBridge.spawn_item(world_ref, x, y, 2, 0)
      roll <= 7  -> GameEngine.NifBridge.spawn_item(world_ref, x, y, 1, 20)
      true       ->
        exp_reward = GameContent.EntityParams.enemy_exp_reward(kind_id)
        GameEngine.NifBridge.spawn_item(world_ref, x, y, 0, exp_reward)
    end
    :ok
  end

  # Phase 3-B: ボス撃破時のアイテムドロップ処理（Gem を10個散布）
  @impl GameEngine.RuleBehaviour
  def on_boss_defeated(world_ref, boss_kind, x, y) do
    exp_reward = GameContent.EntityParams.boss_exp_reward(boss_kind)
    gem_value = div(exp_reward, 10)
    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      GameEngine.NifBridge.spawn_item(world_ref, x + ox, y + oy, 0, gem_value)
    end
    :ok
  end

  # Phase 3-B: ボスAI制御（SlimeKing/BatLord/StoneGolem の AI ロジック）
  # boss_state: {:alive, kind_id, x, y, hp, max_hp, phase_timer} または {:none, ...}
  @impl GameEngine.RuleBehaviour
  def update_boss_ai(context, {:alive, kind_id, bx, by, _hp, _max_hp, phase_timer}) do
    world_ref = context.world_ref
    dt = context.tick_ms / 1000.0
    {px, py} = GameEngine.NifBridge.get_player_pos(world_ref)

    bp = GameContent.EntityParams.boss_params_by_id(kind_id)

    case kind_id do
      # SlimeKing: プレイヤーに向かって直進、特殊行動でスライムをスポーン
      0 ->
        {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
        GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)
        new_timer = if phase_timer - dt <= 0.0 do
          spawn_slimes_around(world_ref, bx, by)
          bp.special_interval
        else
          phase_timer - dt
        end
        GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)

      # BatLord: 通常時はプレイヤーに向かって直進、特殊行動でダッシュ（無敵）
      1 ->
        {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
        GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)
        new_timer = if phase_timer - dt <= 0.0 do
          {dvx, dvy} = chase_velocity(px, py, bx, by, bp.dash_speed)
          GameEngine.NifBridge.set_boss_velocity(world_ref, dvx, dvy)
          GameEngine.NifBridge.set_boss_invincible(world_ref, true)
          Process.send_after(self(), {:boss_dash_end, world_ref}, bp.dash_duration_ms)
          bp.special_interval
        else
          phase_timer - dt
        end
        GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)

      # StoneGolem: プレイヤーに向かって直進、特殊行動で4方向に岩弾を発射
      2 ->
        {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
        GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)
        new_timer = if phase_timer - dt <= 0.0 do
          for {dx, dy} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}] do
            GameEngine.NifBridge.fire_boss_projectile(
              world_ref, dx, dy,
              bp.projectile_speed, bp.projectile_damage, bp.projectile_lifetime
            )
          end
          bp.special_interval
        else
          phase_timer - dt
        end
        GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)

      _ -> :ok
    end
    :ok
  end

  def update_boss_ai(_context, _boss_state), do: :ok

  defp chase_velocity(px, py, bx, by, speed) do
    ddx = px - bx
    ddy = py - by
    dist = :math.sqrt(ddx * ddx + ddy * ddy)
    if dist < 0.001 do
      {0.0, 0.0}
    else
      {ddx / dist * speed, ddy / dist * speed}
    end
  end

  defp spawn_slimes_around(world_ref, bx, by) do
    positions = for i <- 0..7 do
      angle = i * :math.pi() * 2.0 / 8.0
      {bx + :math.cos(angle) * 120.0, by + :math.sin(angle) * 120.0}
    end
    GameEngine.NifBridge.spawn_enemies_at(world_ref, 0, positions)
  end
end
