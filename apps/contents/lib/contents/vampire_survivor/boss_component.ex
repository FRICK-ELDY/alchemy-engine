defmodule Content.VampireSurvivor.BossComponent do
  @moduledoc """
  ボスAI制御・ボス HP 管理・ボスフレームイベント処理を担うコンポーネント。

  Elixir SSoT 移行後: ボス状態は Playing state に保持。
  on_physics_process で移動計算・AI、on_nif_sync で set_special_entity_snapshot を呼ぶ。

  ## on_frame_event
  - `{:boss_damaged, ...}` — ボス HP 減算。boss_hp <= 0 なら撃破処理（Rust は発行しない）。

  ## on_nif_sync
  毎フレーム、Playing state から set_special_entity_snapshot を呼ぶ。
  """
  @behaviour Core.Component

  require Logger

  @item_gem Content.EntityParams.item_kind_gem()
  @boss_slime_king Content.EntityParams.boss_kind_slime_king()
  @boss_bat_lord Content.EntityParams.boss_kind_bat_lord()
  @boss_stone_golem Content.EntityParams.boss_kind_stone_golem()
  @map_width 4096.0
  @map_height 4096.0

  # ── on_frame_event: Rust フレームイベント処理 ──────────────────────

  @impl Core.Component
  def on_frame_event({:boss_damaged, damage_x1000, _, _, _}, context) do
    damage = damage_x1000 / 1000.0
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      playing_scene = content.playing_scene()

      Contents.SceneStack.update_by_module(runner, playing_scene, fn state ->
        if state.boss_hp != nil do
          new_hp = max(0.0, state.boss_hp - damage)
          state = %{state | boss_hp: new_hp}

          if new_hp <= 0.0 do
            apply_defeated(state, context)
          else
            state
          end
        else
          state
        end
      end)
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  defp apply_defeated(state, context) do
    content = Core.Config.current()
    boss_kind = state.boss_kind_id
    exp = content.boss_exp_reward(boss_kind)
    score_delta = content.score_from_exp(exp)
    x = state.boss_x || 0.0
    y = state.boss_y || 0.0

    drop_boss_gems(context.world_ref, x, y, exp)
    Process.delete({__MODULE__, :boss_phase_timer})

    state
    |> Map.update(:score, score_delta, &(&1 + score_delta))
    |> Map.update(:kill_count, 1, &(&1 + 1))
    |> content.playing_scene().accumulate_exp(exp)
    |> content.playing_scene().apply_boss_defeated()
  end

  # ── on_nif_sync: 毎フレームスナップショット注入 ───────────────────

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    snapshot = build_snapshot(playing_state)
    Core.NifBridge.set_special_entity_snapshot(context.world_ref, snapshot)

    :ok
  end

  defp build_snapshot(%{boss_kind_id: nil}), do: :none
  defp build_snapshot(%{boss_hp: nil}), do: :none
  defp build_snapshot(%{boss_hp: hp}) when hp <= 0, do: :none

  defp build_snapshot(state) do
    x = state.boss_x || 0.0
    y = state.boss_y || 0.0
    radius = state.boss_radius || 48.0
    damage = state.boss_damage_per_sec || 30.0
    inv = Map.get(state, :boss_invincible, false)
    {:alive, x, y, radius, damage, inv}
  end

  # ── on_physics_process: ボス AI・移動 ──────────────────────────────

  @impl Core.Component
  def on_physics_process(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner &&
         Contents.SceneStack.get_scene_state(runner, Content.VampireSurvivor.Scenes.Playing)) ||
        %{}

    kind_id = Map.get(playing_state, :boss_kind_id)

    if kind_id != nil do
      update_boss_ai(context, playing_state, kind_id)
    end

    :ok
  end

  @impl Core.Component
  def on_event(_event, _context), do: :ok

  # ── on_engine_message: 遅延コールバック（BatLord ダッシュ終了）──────

  @impl Core.Component
  def on_engine_message({:boss_dash_end, _world_ref}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(runner, content.playing_scene(), fn state ->
        if state.boss_kind_id != nil do
          %{state | boss_invincible: false, boss_vx: 0.0, boss_vy: 0.0}
        else
          state
        end
      end)
    end

    :ok
  end

  def on_engine_message(_msg, _context), do: :ok

  # ── プライベート: アイテムドロップ ────────────────────────────────

  defp drop_boss_gems(world_ref, x, y, exp_reward) do
    gem_value = div(exp_reward, 10)

    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      Core.NifBridge.spawn_item(world_ref, x + ox, y + oy, @item_gem, gem_value)
    end
  end

  # ── プライベート: ボス AI ─────────────────────────────────────────

  defp update_boss_ai(context, state, kind_id) do
    world_ref = context.world_ref
    dt = context.tick_ms / 1000.0
    {px, py} = Core.NifBridge.get_player_pos(world_ref)
    bp = Content.EntityParams.boss_params_by_id(kind_id)

    bx = state.boss_x || px
    by = state.boss_y || py

    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)

    phase_timer = Process.get({__MODULE__, :boss_phase_timer}, bp.special_interval)
    new_timer = phase_timer - dt

    {final_vx, final_vy, new_state} =
      if new_timer <= 0.0 do
        handle_boss_special_action(world_ref, kind_id, px, py, bx, by, bp)
      else
        Process.put({__MODULE__, :boss_phase_timer}, new_timer)
        {vx, vy, nil}
      end

    runner = Core.Config.current().flow_runner(:main)
    playing_scene = Core.Config.current().playing_scene()

    if runner do
      Contents.SceneStack.update_by_module(runner, playing_scene, fn s ->
        new_x = (s.boss_x || 0) + (final_vx || vx) * dt
        new_y = (s.boss_y || 0) + (final_vy || vy) * dt
        r = s.boss_radius || 48.0
        new_x = clamp(new_x, r, @map_width - r)
        new_y = clamp(new_y, r, @map_height - r)

        s
        |> Map.put(:boss_x, new_x)
        |> Map.put(:boss_y, new_y)
        |> Map.put(:boss_vx, final_vx || vx)
        |> Map.put(:boss_vy, final_vy || vy)
        |> maybe_apply_special_state(new_state)
      end)
    end
  end

  defp maybe_apply_special_state(state, nil), do: state

  defp maybe_apply_special_state(state, %{invincible: true, vx: vx, vy: vy}) do
    %{state | boss_invincible: true, boss_vx: vx, boss_vy: vy}
  end

  defp maybe_apply_special_state(state, _), do: state

  defp handle_boss_special_action(world_ref, @boss_slime_king, px, py, bx, by, bp) do
    spawn_slimes_around(world_ref, bx, by)
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
    {vx, vy, nil}
  end

  defp handle_boss_special_action(_world_ref, @boss_bat_lord, px, py, bx, by, bp) do
    {dvx, dvy} = chase_velocity(px, py, bx, by, bp.dash_speed)
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    Process.send_after(self(), {:boss_dash_end, nil}, bp.dash_duration_ms)
    {dvx, dvy, %{invincible: true, vx: dvx, vy: dvy}}
  end

  defp handle_boss_special_action(world_ref, @boss_stone_golem, px, py, boss_x, boss_y, bp) do
    for {dx, dy} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}] do
      Core.NifBridge.spawn_projectile(
        world_ref,
        boss_x,
        boss_y,
        dx * bp.projectile_speed,
        dy * bp.projectile_speed,
        bp.projectile_damage,
        bp.projectile_lifetime,
        14
      )
    end

    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {vx, vy} = chase_velocity(px, py, boss_x, boss_y, bp.speed)
    {vx, vy, nil}
  end

  defp handle_boss_special_action(_world_ref, _kind_id, _px, _py, _bx, _by, bp) do
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {0.0, 0.0, nil}
  end

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
    positions =
      for i <- 0..7 do
        angle = i * :math.pi() * 2.0 / 8.0
        {bx + :math.cos(angle) * 120.0, by + :math.sin(angle) * 120.0}
      end

    Core.NifBridge.spawn_enemies_at(
      world_ref,
      Content.EntityParams.enemy_kind_slime(),
      positions
    )
  end

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _, _), do: v
end
