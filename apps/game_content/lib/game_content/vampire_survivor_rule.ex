defmodule GameContent.VampireSurvivorRule do
  @moduledoc """
  ヴァンパイアサバイバーの RuleBehaviour 実装。

  シーン構成・ゲームロジック・スポーン/ボス/レベルアップの制御を定義する。
  `VampireSurvivorWorld` と組み合わせて使用する。
  """
  @behaviour GameEngine.RuleBehaviour

  # ── アイテムドロップ確率（累積、1〜100 の乱数と比較）──────────────
  # Magnet: 2%、Potion: 5%（累積 7%）、Gem: 残り 93%
  @drop_magnet_threshold 2
  @drop_potion_threshold 7

  # ── アイテム種別 ID（Rust の ItemKind と対応）──────────────────────
  @item_gem    0
  @item_potion 1
  @item_magnet 2

  # ── Potion の回復量 ────────────────────────────────────────────────
  @potion_heal_value 20

  # ── ボス種別 ID（EntityParams の値と同値・パターンマッチ用）──────────
  @boss_slime_king  0
  @boss_bat_lord    1
  @boss_stone_golem 2

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
  def initial_weapons, do: [:magic_wand]

  @impl GameEngine.RuleBehaviour
  def enemy_exp_reward(enemy_kind), do: GameContent.EntityParams.enemy_exp_reward(enemy_kind)

  @impl GameEngine.RuleBehaviour
  def boss_exp_reward(boss_kind), do: GameContent.EntityParams.boss_exp_reward(boss_kind)

  @impl GameEngine.RuleBehaviour
  def score_from_exp(exp), do: GameContent.EntityParams.score_from_exp(exp)

  @impl GameEngine.RuleBehaviour
  def wave_label(elapsed_sec) do
    GameContent.VampireSurvivor.SpawnSystem.wave_label(elapsed_sec)
  end

  # Phase 3-B: 敵撃破時のアイテムドロップ処理
  # 注意: :rand はプロセスローカルな非決定的 RNG を使用する。
  # 以前の Rust 実装はシード付き SimpleRng で決定的だったが、Phase 3-B では
  # リプレイ機能・テスト再現性は要件外のため意図的に非決定的な実装を採用している。
  # 将来リプレイ機能が必要になった場合は、GameEvents の state 経由でシード付き
  # RNG 状態を引き回し、context 経由でコールバックに渡す設計に変更すること。
  @impl GameEngine.RuleBehaviour
  def on_entity_removed(world_ref, kind_id, x, y) do
    roll = :rand.uniform(100)
    cond do
      roll <= @drop_magnet_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)
      roll <= @drop_potion_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)
      true ->
        exp_reward = GameContent.EntityParams.enemy_exp_reward(kind_id)
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp_reward)
    end
    :ok
  end

  # Phase 3-B: ボス撃破時のアイテムドロップ処理（Gem を10個散布）
  # on_entity_removed と同様に :rand による非決定的 RNG を使用（意図的）。
  @impl GameEngine.RuleBehaviour
  def on_boss_defeated(world_ref, boss_kind, x, y) do
    exp_reward = GameContent.EntityParams.boss_exp_reward(boss_kind)
    gem_value = div(exp_reward, 10)
    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      GameEngine.NifBridge.spawn_item(world_ref, x + ox, y + oy, @item_gem, gem_value)
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

    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
    GameEngine.NifBridge.set_boss_velocity(world_ref, vx, vy)

    new_timer = if phase_timer - dt <= 0.0 do
      handle_boss_special_action(world_ref, kind_id, px, py, bx, by, bp)
      bp.special_interval
    else
      phase_timer - dt
    end
    GameEngine.NifBridge.set_boss_phase_timer(world_ref, new_timer)
    :ok
  end

  def update_boss_ai(_context, _boss_state), do: :ok

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
