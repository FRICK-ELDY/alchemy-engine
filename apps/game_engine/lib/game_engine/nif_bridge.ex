defmodule GameEngine.NifBridge do
  @moduledoc """
  Rust NIF のラッパーモジュール。
  `use Rustler` により、コンパイル時に `native/game_nif` クレートが
  自動的にビルドされ、`.dll` がロードされる。
  """

  use Rustler,
    otp_app: :game_engine,
    crate: :game_nif,
    path: "../../native/game_nif"

  # ── control ───────────────────────────────────────────────────────
  def create_world do
    :erlang.nif_error(:nif_not_loaded)
  end

  def set_map_obstacles(_world, _obstacles), do: :erlang.nif_error(:nif_not_loaded)
  def physics_step(_world, _delta_ms), do: :erlang.nif_error(:nif_not_loaded)
  def drain_frame_events(_world), do: :erlang.nif_error(:nif_not_loaded)
  def set_player_input(_world, _dx, _dy), do: :erlang.nif_error(:nif_not_loaded)
  def spawn_enemies(_world, _kind, _count), do: :erlang.nif_error(:nif_not_loaded)
  # Phase 3-B: 指定座標リストに敵をスポーンする NIF
  def spawn_enemies_at(_world, _kind, _positions), do: :erlang.nif_error(:nif_not_loaded)

  # I-2: 武器スロットを Elixir 側から毎フレーム注入する NIF（add_weapon の代替）
  # slots: [{kind_id, level}] のリスト
  def set_weapon_slots(_world, _slots), do: :erlang.nif_error(:nif_not_loaded)
  # Phase R-3: spawn_boss を汎用化（ボスという概念を NIF 層から排除）
  def spawn_special_entity(_world, _kind_id), do: :erlang.nif_error(:nif_not_loaded)

  # Phase R-3: spawn_elite_enemy を汎用化（エリートという概念を NIF 層から排除）
  def spawn_enemies_with_hp_multiplier(_world, _kind_id, _count, _hp_multiplier),
    do: :erlang.nif_error(:nif_not_loaded)

  # Phase 3-C: スコアポップアップを描画用バッファに追加する NIF
  def add_score_popup(_world, _x, _y, _value), do: :erlang.nif_error(:nif_not_loaded)
  # Phase 3-B: Elixir 側のルールがアイテムドロップを制御するための NIF
  # kind: 0=Gem, 1=Potion, 2=Magnet
  def spawn_item(_world, _x, _y, _kind, _value), do: :erlang.nif_error(:nif_not_loaded)

  # Phase R-3: 汎用エンティティ操作 NIF
  # entity_id: :boss
  def set_entity_velocity(_world, _entity_id, _vx, _vy), do: :erlang.nif_error(:nif_not_loaded)
  # entity_id: :boss, flag: :invincible
  def set_entity_flag(_world, _entity_id, _flag, _value), do: :erlang.nif_error(:nif_not_loaded)
  # entity_id: :boss または {:enemy, index}
  def set_entity_hp(_world, _entity_id, _hp), do: :erlang.nif_error(:nif_not_loaded)

  # x/y は発射座標、vx/vy は速度ベクトル（正規化済み × speed）、kind は BULLET_KIND_* 定数
  def spawn_projectile(_world, _x, _y, _vx, _vy, _damage, _lifetime, _kind),
    do: :erlang.nif_error(:nif_not_loaded)

  def create_game_loop_control, do: :erlang.nif_error(:nif_not_loaded)
  def start_rust_game_loop(_world, _control, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def create_render_frame_buffer, do: :erlang.nif_error(:nif_not_loaded)

  # title: ウィンドウタイトル文字列
  # atlas_path: アトラス PNG のファイルパス（Rust 側でロード、存在しない場合は埋め込みフォールバック）
  def start_render_thread(_world, _render_buf, _pid, _title, _atlas_path),
    do: :erlang.nif_error(:nif_not_loaded)

  # Phase R-2: Elixir 側から DrawCommand リストを RenderFrameBuffer に push する
  # commands: DrawCommand タプルのリスト
  #   {:player_sprite, x, y, frame}
  #   {:sprite, x, y, kind_id, frame}
  #   {:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
  #   {:particle, x, y, r, g, b, {alpha, size}}
  #   {:item, x, y, kind}
  #   {:obstacle, x, y, radius, kind}
  # camera:   {:camera_2d, offset_x, offset_y}
  # hud:      ネストタプル形式（render_frame_nif.rs の decode_hud を参照）
  #           { {hp, max_hp, score, elapsed_sec, level, exp, exp_to_next},
  #             {enemy_count, bullet_count, fps, level_up_pending},
  #             {weapon_choices, weapon_upgrade_descs, weapon_levels},
  #             {magnet_timer, item_count, boss_info, phase, flash_alpha, score_popups, kill_count},
  #             {overlay, title_overlay} }
  #   phase: :title | :playing | :overlay | :game_over
  #   overlay: :none | {title, title_color, subtitle, bg_color, border_color, buttons}
  #   title_overlay: :none | {game_title, title_color, description, instructions, bg_color, border_color, buttons}
  def push_render_frame(_render_buf, _commands, _camera, _hud),
    do: :erlang.nif_error(:nif_not_loaded)

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
  def get_magnet_timer(_world), do: :erlang.nif_error(:nif_not_loaded)
  # I-2: ボスAI制御用（{:alive, x, y, hp, max_hp, phase_timer} または :none）
  # ボス種別（kind_id）は Elixir 側 Rule state で管理するため返り値から除去
  def get_boss_state(_world), do: :erlang.nif_error(:nif_not_loaded)
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_player_dead(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── Elixir SSoT 注入 NIF（毎フレーム呼ばれる）──────────────────────
  def set_player_hp(_world, _hp), do: :erlang.nif_error(:nif_not_loaded)
  def set_elapsed_seconds(_world, _elapsed), do: :erlang.nif_error(:nif_not_loaded)

  # ── Phase 3-A: World パラメータ注入 NIF ──────────────────────────
  # ワールド生成後に一度だけ呼び出す。
  def set_world_size(_world, _width, _height), do: :erlang.nif_error(:nif_not_loaded)
  # enemies: [{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, passes_obstacles}]
  # weapons: [{cooldown, damage, as_u8, name, bullet_table_or_nil}]
  # bosses:  [{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, special_interval}]
  def set_entity_params(_world, _enemies, _weapons, _bosses),
    do: :erlang.nif_error(:nif_not_loaded)

  # ── Push 型同期 NIF ────────────────────────────────────────────
  def push_tick(_world, _dx, _dy, _delta_ms), do: :erlang.nif_error(:nif_not_loaded)

  # ── Phase R-2: 描画用エンティティスナップショット ──────────────────
  # 戻り値: {player_x, player_y, frame_id, enemies, bullets, particles,
  #          items, obstacles, boss, score_popups}
  def get_render_entities(_world), do: :erlang.nif_error(:nif_not_loaded)

  # Phase R-2: 武器アップグレード説明文を返す NIF
  # weapon_choices: ["weapon_0", "weapon_2", ...]
  # weapon_slots: [{kind_id, level}]
  # 戻り値: [[desc_string]]
  def get_weapon_upgrade_descs(_world, _weapon_choices, _weapon_slots),
    do: :erlang.nif_error(:nif_not_loaded)

  # ── 移行検証用（フェーズ0）───────────────────────────────────────
  def get_full_game_state(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── snapshot_heavy（明示操作時のみ）──────────────────────────────
  def get_save_snapshot(_world), do: :erlang.nif_error(:nif_not_loaded)
  def load_save_snapshot(_world, _snapshot), do: :erlang.nif_error(:nif_not_loaded)
  def debug_dump_world(_world), do: :erlang.nif_error(:nif_not_loaded)
end
