defmodule GameEngine.NifBridge.Behaviour do
  @moduledoc """
  `GameEngine.NifBridge` の Behaviour 定義。

  テスト時に `Mox` でモック化するために使用する。
  本番コードは `GameEngine.NifBridge` が直接 NIF を呼び出すため、
  このビヘイビアを `@behaviour` として宣言する必要はない。
  """

  # ── control ───────────────────────────────────────────────────────
  @callback create_world() :: reference()
  @callback set_map_obstacles(reference(), list()) :: :ok
  @callback physics_step(reference(), non_neg_integer()) :: :ok
  @callback drain_frame_events(reference()) :: list()
  @callback set_player_input(reference(), float(), float()) :: :ok
  @callback spawn_enemies(reference(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback spawn_enemies_at(reference(), non_neg_integer(), list()) :: :ok
  # I-2: add_weapon は廃止。set_weapon_slots で毎フレーム注入する。
  @callback set_weapon_slots(reference(), list()) :: :ok
  @callback spawn_boss(reference(), non_neg_integer()) :: :ok
  @callback spawn_elite_enemy(reference(), non_neg_integer(), non_neg_integer(), float()) :: :ok
  @callback add_score_popup(reference(), float(), float(), non_neg_integer()) :: :ok
  @callback spawn_item(reference(), float(), float(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback set_boss_velocity(reference(), float(), float()) :: :ok
  @callback set_boss_invincible(reference(), boolean()) :: :ok
  @callback set_boss_phase_timer(reference(), float()) :: :ok
  @callback fire_boss_projectile(reference(), float(), float(), float(), non_neg_integer(), float()) :: :ok
  @callback create_game_loop_control() :: reference()
  @callback start_rust_game_loop(reference(), reference(), pid()) :: :ok
  @callback start_render_thread(reference(), pid()) :: :ok
  @callback pause_physics(reference()) :: :ok
  @callback resume_physics(reference()) :: :ok

  # ── query_light ───────────────────────────────────────────────────
  @callback get_player_pos(reference()) :: {float(), float()}
  @callback get_player_hp(reference()) :: float()
  @callback get_bullet_count(reference()) :: non_neg_integer()
  @callback get_frame_time_ms(reference()) :: float()
  @callback get_enemy_count(reference()) :: non_neg_integer()
  @callback get_hud_data(reference()) :: map()
  @callback get_frame_metadata(reference()) :: map()
  @callback get_magnet_timer(reference()) :: float()
  # I-2: kind_id を返り値から除去。ボス種別は Elixir 側 Rule state で管理する。
  @callback get_boss_state(reference()) :: {:alive, float(), float(), float(), float(), float()} | :none
  @callback is_player_dead(reference()) :: boolean()

  # ── Elixir SSoT 注入 NIF ─────────────────────────────────────────
  @callback set_player_hp(reference(), float()) :: :ok
  @callback set_hud_level_state(reference(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean(), list()) :: :ok
  @callback set_elapsed_seconds(reference(), float()) :: :ok
  @callback set_boss_hp(reference(), float()) :: :ok
  @callback set_hud_state(reference(), non_neg_integer(), non_neg_integer()) :: :ok

  # ── Phase 3-A: World パラメータ注入 NIF ──────────────────────────
  @callback set_world_size(reference(), float(), float()) :: :ok
  @callback set_entity_params(reference(), list(), list(), list()) :: :ok

  # ── Push 型同期 NIF ────────────────────────────────────────────
  @callback push_tick(reference(), float(), float(), non_neg_integer()) :: :ok

  # ── 移行検証用 ───────────────────────────────────────────────────
  @callback get_full_game_state(reference()) :: map()

  # ── snapshot_heavy ────────────────────────────────────────────────
  @callback get_save_snapshot(reference()) :: binary()
  @callback load_save_snapshot(reference(), binary()) :: :ok
  @callback debug_dump_world(reference()) :: binary()
end
