defmodule GameEngine.NifBridge do
  @moduledoc """
  Rust NIF のラッパーモジュール。
  `use Rustler` により、コンパイル時に `native/game_native` クレートが
  自動的にビルドされ、`.dll` がロードされる。
  """

  use Rustler,
    otp_app: :game_engine,
    crate: :game_native,
    path: "../../native/game_native"

  # ── control ───────────────────────────────────────────────────────
  def create_world() do
    :erlang.nif_error(:nif_not_loaded)
  end
  def set_map_obstacles(_world, _obstacles), do: :erlang.nif_error(:nif_not_loaded)
  def physics_step(_world, _delta_ms), do: :erlang.nif_error(:nif_not_loaded)
  def drain_frame_events(_world), do: :erlang.nif_error(:nif_not_loaded)
  def set_player_input(_world, _dx, _dy), do: :erlang.nif_error(:nif_not_loaded)
  def spawn_enemies(_world, _kind, _count), do: :erlang.nif_error(:nif_not_loaded)
  def add_weapon(_world, _weapon_name), do: :erlang.nif_error(:nif_not_loaded)
  def skip_level_up(_world), do: :erlang.nif_error(:nif_not_loaded)
  def spawn_boss(_world, _kind), do: :erlang.nif_error(:nif_not_loaded)
  def spawn_elite_enemy(_world, _kind, _count, _hp_multiplier), do: :erlang.nif_error(:nif_not_loaded)
  def create_game_loop_control(), do: :erlang.nif_error(:nif_not_loaded)
  def start_rust_game_loop(_world, _control, _pid), do: :erlang.nif_error(:nif_not_loaded)
  def start_render_thread(_world), do: :erlang.nif_error(:nif_not_loaded)
  def pause_physics(_control), do: :erlang.nif_error(:nif_not_loaded)
  def resume_physics(_control), do: :erlang.nif_error(:nif_not_loaded)

  # ── query_light（毎フレーム利用可）───────────────────────────────
  def get_player_pos(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_player_hp(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_bullet_count(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_frame_time_ms(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_enemy_count(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_hud_data(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_frame_metadata(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_level_up_data(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_weapon_levels(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_magnet_timer(_world), do: :erlang.nif_error(:nif_not_loaded)
  def get_boss_info(_world), do: :erlang.nif_error(:nif_not_loaded)
  def is_player_dead(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── snapshot_heavy（明示操作時のみ）──────────────────────────────
  def get_save_snapshot(_world), do: :erlang.nif_error(:nif_not_loaded)
  def load_save_snapshot(_world, _snapshot), do: :erlang.nif_error(:nif_not_loaded)
  def debug_dump_world(_world), do: :erlang.nif_error(:nif_not_loaded)
end
