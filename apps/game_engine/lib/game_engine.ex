defmodule GameEngine do
  @moduledoc """
  ゲームエンジンの安定化された公開 API。

  ゲームは **GameEngine モジュール経由でのみ** エンジンとやり取りする。
  """

  alias GameEngine.NifBridge

  # ── World 操作（ゲームから利用）───────────────────────────────────────

  def spawn_enemies(world_ref, kind, count) do
    kind_id = resolve_enemy_id(kind)
    NifBridge.spawn_enemies(world_ref, kind_id, count)
  end

  def spawn_elite_enemy(world_ref, kind, count, hp_multiplier) do
    kind_id = resolve_enemy_id(kind)
    NifBridge.spawn_elite_enemy(world_ref, kind_id, count, hp_multiplier)
  end

  def get_enemy_count(world_ref) do
    NifBridge.get_enemy_count(world_ref)
  end

  def player_dead?(world_ref) do
    NifBridge.is_player_dead(world_ref)
  end

  def get_frame_metadata(world_ref) do
    NifBridge.get_frame_metadata(world_ref)
  end

  def save_session(world_ref), do: GameEngine.SaveManager.save_session(world_ref)
  def load_session(world_ref), do: GameEngine.SaveManager.load_session(world_ref)
  def has_save?, do: GameEngine.SaveManager.has_save?()
  def save_high_score(score), do: GameEngine.SaveManager.save_high_score(score)
  def load_high_scores, do: GameEngine.SaveManager.load_high_scores()

  # ── エンジン内部用（GameEvents が使用）───────────────────────────────

  def create_world, do: NifBridge.create_world()

  def set_map_obstacles(world_ref, obstacles),
    do: NifBridge.set_map_obstacles(world_ref, obstacles)

  def create_game_loop_control, do: NifBridge.create_game_loop_control()

  def start_rust_game_loop(world_ref, control_ref, pid),
    do: NifBridge.start_rust_game_loop(world_ref, control_ref, pid)

  def start_render_thread(world_ref, pid), do: NifBridge.start_render_thread(world_ref, pid)
  def pause_physics(control_ref), do: NifBridge.pause_physics(control_ref)
  def resume_physics(control_ref), do: NifBridge.resume_physics(control_ref)
  def physics_step(world_ref, delta_ms), do: NifBridge.physics_step(world_ref, delta_ms)
  def set_player_input(world_ref, dx, dy), do: NifBridge.set_player_input(world_ref, dx, dy)
  def drain_frame_events(world_ref), do: NifBridge.drain_frame_events(world_ref)

  # ── ID 解決（entity_registry 経由）──────────────────────────────────

  defp resolve_enemy_id(kind) when is_atom(kind) do
    GameEngine.Config.current().entity_registry().enemies[kind] ||
      raise "Unknown enemy kind: #{inspect(kind)}"
  end
end
