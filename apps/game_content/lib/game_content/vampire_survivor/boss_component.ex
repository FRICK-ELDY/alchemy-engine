defmodule GameContent.VampireSurvivor.BossComponent do
  @moduledoc """
  ボスAI制御・ボス HP NIF 注入・ボスフレームイベント処理を担うコンポーネント。

  ## on_frame_event
  - `{:boss_spawn, ...}`   — ボス状態の初期化（Playing シーン state を更新）
  - `{:boss_damaged, ...}` — ボス HP 減算（Playing シーン state を更新）
  - `{:boss_defeated, ...}` — スコア更新・アイテムドロップ

  ## on_nif_sync
  毎フレーム、Playing シーン state の boss_hp を NIF に注入する。
  ダーティフラグはプロセス辞書で管理する。
  """
  @behaviour GameEngine.Component

  require Logger

  @item_gem GameContent.EntityParams.item_kind_gem()

  @boss_slime_king GameContent.EntityParams.boss_kind_slime_king()
  @boss_bat_lord GameContent.EntityParams.boss_kind_bat_lord()
  @boss_stone_golem GameContent.EntityParams.boss_kind_stone_golem()

  # ── on_frame_event: Rust フレームイベント処理 ──────────────────────

  @impl GameEngine.Component
  def on_frame_event({:boss_spawn, boss_kind, _, _, _}, _context) do
    content = GameEngine.Config.current()

    GameEngine.SceneManager.update_by_module(content.playing_scene(), fn state ->
      max_hp = GameContent.EntityParams.boss_max_hp(boss_kind)
      %{state | boss_hp: max_hp, boss_max_hp: max_hp, boss_kind_id: boss_kind}
    end)

    :ok
  end

  def on_frame_event({:boss_damaged, damage_x1000, _, _, _}, _context) do
    damage = damage_x1000 / 1000.0
    content = GameEngine.Config.current()

    GameEngine.SceneManager.update_by_module(content.playing_scene(), fn state ->
      if state.boss_hp != nil do
        %{state | boss_hp: max(0.0, state.boss_hp - damage)}
      else
        state
      end
    end)

    :ok
  end

  def on_frame_event({:boss_defeated, world_ref, boss_kind, x, y}, _context) do
    content = GameEngine.Config.current()

    if function_exported?(content, :boss_exp_reward, 1) do
      exp = content.boss_exp_reward(boss_kind)
      score_delta = content.score_from_exp(exp)

      GameEngine.SceneManager.update_by_module(content.playing_scene(), fn state ->
        state
        |> Map.update(:score, score_delta, &(&1 + score_delta))
        |> Map.update(:kill_count, 1, &(&1 + 1))
        |> content.playing_scene().accumulate_exp(exp)
        |> content.playing_scene().apply_boss_defeated()
      end)

      drop_boss_gems(world_ref, x, y, exp)
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  # ── on_nif_sync: 毎フレーム NIF 注入 ─────────────────────────────

  @impl GameEngine.Component
  def on_nif_sync(context) do
    content = GameEngine.Config.current()
    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}
    boss_hp = Map.get(playing_state, :boss_hp)
    prev = Process.get({__MODULE__, :last_boss_hp}, :unset)

    if boss_hp != prev do
      push_boss_hp_to_nif(context.world_ref, boss_hp)
      Process.put({__MODULE__, :last_boss_hp}, boss_hp)
    end

    :ok
  end

  # ── on_physics_process: ボス AI 制御 ─────────────────────────────

  @impl GameEngine.Component
  def on_physics_process(context) do
    world_ref = context.world_ref

    playing_state =
      GameEngine.SceneManager.get_scene_state(GameContent.VampireSurvivor.Scenes.Playing)

    kind_id = Map.get(playing_state || %{}, :boss_kind_id)

    if kind_id != nil do
      boss_state = GameEngine.NifBridge.get_boss_state(world_ref)
      update_boss_ai(context, boss_state, kind_id)
    end

    :ok
  end

  @impl GameEngine.Component
  def on_event(_event, _context), do: :ok

  # ── プライベート: NIF 注入 ────────────────────────────────────────

  defp push_boss_hp_to_nif(_world_ref, nil), do: :ok

  defp push_boss_hp_to_nif(world_ref, boss_hp) do
    case GameEngine.NifBridge.set_boss_hp(world_ref, boss_hp) do
      {:error, reason} ->
        Logger.error("[NIF ERROR] set_boss_hp failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  # ── プライベート: アイテムドロップ ────────────────────────────────

  defp drop_boss_gems(world_ref, x, y, exp_reward) do
    gem_value = div(exp_reward, 10)

    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      GameEngine.NifBridge.spawn_item(world_ref, x + ox, y + oy, @item_gem, gem_value)
    end
  end

  # ── プライベート: ボス AI ─────────────────────────────────────────

  defp update_boss_ai(context, {:alive, bx, by, _hp, _max_hp, phase_timer}, kind_id) do
    world_ref = context.world_ref
    dt = context.tick_ms / 1000.0
    {px, py} = GameEngine.NifBridge.get_player_pos(world_ref)
    bp = GameContent.EntityParams.boss_params_by_id(kind_id)

    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
    GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)

    new_timer =
      if phase_timer - dt <= 0.0 do
        handle_boss_special_action(world_ref, kind_id, px, py, bx, by, bp)
        bp.special_interval
      else
        phase_timer - dt
      end

    GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)
    :ok
  end

  defp update_boss_ai(_context, _boss_state, _kind_id), do: :ok

  defp handle_boss_special_action(world_ref, @boss_slime_king, _px, _py, bx, by, _bp) do
    spawn_slimes_around(world_ref, bx, by)
  end

  defp handle_boss_special_action(world_ref, @boss_bat_lord, px, py, bx, by, bp) do
    {dvx, dvy} = chase_velocity(px, py, bx, by, bp.dash_speed)
    GameEngine.NifBridge.set_boss_velocity(world_ref, dvx, dvy)
    GameEngine.NifBridge.set_boss_invincible(world_ref, true)
    Process.send_after(self(), {:boss_dash_end, world_ref}, bp.dash_duration_ms)
  end

  defp handle_boss_special_action(world_ref, @boss_stone_golem, _px, _py, _bx, _by, bp) do
    for {dx, dy} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}] do
      GameEngine.NifBridge.fire_boss_projectile(
        world_ref,
        dx,
        dy,
        bp.projectile_speed,
        bp.projectile_damage,
        bp.projectile_lifetime
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
    positions =
      for i <- 0..7 do
        angle = i * :math.pi() * 2.0 / 8.0
        {bx + :math.cos(angle) * 120.0, by + :math.sin(angle) * 120.0}
      end

    GameEngine.NifBridge.spawn_enemies_at(
      world_ref,
      GameContent.EntityParams.enemy_kind_slime(),
      positions
    )
  end
end
