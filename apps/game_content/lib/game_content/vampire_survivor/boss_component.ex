defmodule GameContent.VampireSurvivor.BossComponent do
  @moduledoc """
  ボスAI制御・ボス撃破時のアイテムドロップを担うコンポーネント。

  旧 `GameContent.VampireSurvivorRule` の `update_boss_ai/2` および
  `on_boss_defeated/4` の責務を引き継ぐ。
  """
  @behaviour GameEngine.Component

  # ── アイテム種別 ID（EntityParams から取得）──────────────────────
  @item_gem GameContent.EntityParams.item_kind_gem()

  # ── ボス種別 ID（EntityParams から取得してパターンマッチ用定数に束縛）──
  @boss_slime_king  GameContent.EntityParams.boss_kind_slime_king()
  @boss_bat_lord    GameContent.EntityParams.boss_kind_bat_lord()
  @boss_stone_golem GameContent.EntityParams.boss_kind_stone_golem()

  @impl GameEngine.Component
  def on_physics_process(context) do
    world_ref = context.world_ref
    playing_state = GameEngine.SceneManager.get_scene_state(GameContent.VampireSurvivor.Scenes.Playing)
    scene_boss_kind_id = Map.get(playing_state, :boss_kind_id)

    if scene_boss_kind_id != nil do
      boss_state = GameEngine.NifBridge.get_boss_state(world_ref)
      update_boss_ai(context, boss_state)
    end

    :ok
  end

  @impl GameEngine.Component
  def on_event({:boss_defeated, world_ref, boss_kind, x, y}, _context) do
    exp_reward = GameContent.EntityParams.boss_exp_reward(boss_kind)
    gem_value = div(exp_reward, 10)
    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      GameEngine.NifBridge.spawn_item(world_ref, x + ox, y + oy, @item_gem, gem_value)
    end
    :ok
  end

  def on_event(_event, _context), do: :ok

  # ── ボスAI ────────────────────────────────────────────────────────

  # I-2: get_boss_state の返り値から kind_id が除去されたため、
  # ボス種別は Playing シーン state の boss_kind_id から取得する。
  defp update_boss_ai(context, {:alive, bx, by, _hp, _max_hp, phase_timer}) do
    world_ref = context.world_ref
    dt = context.tick_ms / 1000.0
    {px, py} = GameEngine.NifBridge.get_player_pos(world_ref)

    playing_state = GameEngine.SceneManager.get_scene_state(GameContent.VampireSurvivor.Scenes.Playing)
    kind_id = Map.get(playing_state, :boss_kind_id)

    if kind_id != nil do
      bp = GameContent.EntityParams.boss_params_by_id(kind_id)

      {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
      GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)

      new_timer = if phase_timer - dt <= 0.0 do
        handle_boss_special_action(world_ref, kind_id, px, py, bx, by, bp)
        bp.special_interval
      else
        phase_timer - dt
      end
      GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)
    end
    :ok
  end

  defp update_boss_ai(_context, _boss_state), do: :ok

  # SlimeKing: スライムをスポーン
  defp handle_boss_special_action(world_ref, @boss_slime_king, _px, _py, bx, by, _bp) do
    spawn_slimes_around(world_ref, bx, by)
  end

  # BatLord: ダッシュ（速度上書き・無敵付与）
  defp handle_boss_special_action(world_ref, @boss_bat_lord, px, py, bx, by, bp) do
    {dvx, dvy} = chase_velocity(px, py, bx, by, bp.dash_speed)
    GameEngine.NifBridge.set_boss_velocity(world_ref, dvx, dvy)
    GameEngine.NifBridge.set_boss_invincible(world_ref, true)
    Process.send_after(self(), {:boss_dash_end, world_ref}, bp.dash_duration_ms)
  end

  # StoneGolem: 4方向に岩弾を発射
  defp handle_boss_special_action(world_ref, @boss_stone_golem, _px, _py, _bx, _by, bp) do
    for {dx, dy} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}] do
      GameEngine.NifBridge.fire_boss_projectile(
        world_ref, dx, dy,
        bp.projectile_speed, bp.projectile_damage, bp.projectile_lifetime
      )
    end
  end

  defp handle_boss_special_action(_world_ref, _kind_id, _px, _py, _bx, _by, _bp), do: :ok

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
    GameEngine.NifBridge.spawn_enemies_at(world_ref, GameContent.EntityParams.enemy_kind_slime(), positions)
  end
end
