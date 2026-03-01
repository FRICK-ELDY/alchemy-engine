defmodule GameEngine.NifBridge.Behaviour do
  @moduledoc false

  # control
  @callback create_world() :: reference()
  @callback set_map_obstacles(reference(), list()) :: :ok
  @callback physics_step(reference(), non_neg_integer()) :: :ok
  @callback drain_frame_events(reference()) :: list()
  @callback set_player_input(reference(), number(), number()) :: :ok
  @callback spawn_enemies(reference(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback spawn_enemies_at(reference(), non_neg_integer(), list()) :: :ok
  @callback set_weapon_slots(reference(), list()) :: :ok
  @callback spawn_boss(reference(), non_neg_integer()) :: :ok
  @callback spawn_elite_enemy(reference(), non_neg_integer(), non_neg_integer(), number()) :: :ok
  @callback add_score_popup(reference(), number(), number(), non_neg_integer()) :: :ok
  @callback spawn_item(reference(), number(), number(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback set_boss_velocity(reference(), number(), number()) :: :ok
  @callback set_boss_invincible(reference(), boolean()) :: :ok
  @callback set_boss_phase_timer(reference(), number()) :: :ok
  @callback fire_boss_projectile(reference(), number(), number(), number(), number(), number()) :: :ok
  @callback create_game_loop_control() :: reference()
  @callback start_rust_game_loop(reference(), reference(), pid()) :: :ok
  @callback start_render_thread(reference(), pid()) :: :ok
  @callback pause_physics(reference()) :: :ok
  @callback resume_physics(reference()) :: :ok

  # query_light
  @callback get_player_pos(reference()) :: {number(), number()}
  @callback get_player_hp(reference()) :: number()
  @callback get_bullet_count(reference()) :: non_neg_integer()
  @callback get_frame_time_ms(reference()) :: number()
  @callback get_enemy_count(reference()) :: non_neg_integer()
  @callback get_hud_data(reference()) :: term()
  @callback get_frame_metadata(reference()) :: term()
  @callback get_magnet_timer(reference()) :: number()
  @callback get_boss_state(reference()) :: term()
  @callback player_dead?(reference()) :: boolean()

  # Elixir SSoT 注入
  @callback set_player_hp(reference(), number()) :: :ok
  @callback set_hud_level_state(reference(), non_neg_integer(), number(), number(), boolean(), list()) :: :ok
  @callback set_elapsed_seconds(reference(), number()) :: :ok
  @callback set_boss_hp(reference(), number()) :: :ok
  @callback set_hud_state(reference(), non_neg_integer(), non_neg_integer()) :: :ok

  # World パラメータ注入
  @callback set_world_size(reference(), number(), number()) :: :ok
  @callback set_entity_params(reference(), list(), list(), list()) :: :ok

  # Push 型同期
  @callback push_tick(reference(), number(), number(), non_neg_integer()) :: :ok

  # 移行検証用
  @callback get_full_game_state(reference()) :: term()

  # snapshot_heavy
  @callback get_save_snapshot(reference()) :: term()
  @callback load_save_snapshot(reference(), term()) :: :ok
  @callback debug_dump_world(reference()) :: term()
end
