defmodule Core.NifBridge do
  @moduledoc """
  Rust NIF のラッパーモジュール。
  `use Rustler` により、コンパイル時に `native/nif` クレートが
  自動的にビルドされ、`.dll` がロードされる。

  VR 対応ビルド: `config :core, Core.NifBridge, features: ["xr"]`
  を設定すると、mix compile 時に nif に --features xr が渡される。
  """

  use Rustler,
    otp_app: :core,
    crate: :nif,
    path: "../../native/nif"

  # ── control ───────────────────────────────────────────────────────
  def create_world do
    :erlang.nif_error(:nif_not_loaded)
  end

  def set_map_obstacles(_world, _obstacles), do: :erlang.nif_error(:nif_not_loaded)
  def physics_step(_world, _delta_ms), do: :erlang.nif_error(:nif_not_loaded)
  def drain_frame_events(_world), do: :erlang.nif_error(:nif_not_loaded)
  def set_player_input(_world, _dx, _dy), do: :erlang.nif_error(:nif_not_loaded)

  # P5-1: 複数注入を 1 回の write lock で適用するバッチ NIF。
  # injection_map: オプショナルキーを持つ map。存在するキーのみ適用。
  def set_frame_injection(_world, _injection_map), do: :erlang.nif_error(:nif_not_loaded)

  # P5: protobuf バイナリ形式の set_frame_injection。decode オーバーヘッド削減。
  def set_frame_injection_binary(_world, _binary), do: :erlang.nif_error(:nif_not_loaded)

  # P5: RenderFrame protobuf（`Content.FrameEncoder` と同一スキーマ）のデコード検証用。NIF は描画を持たない。
  def push_render_frame_binary(_world, _binary), do: :erlang.nif_error(:nif_not_loaded)
  def spawn_enemies(_world, _kind, _count), do: :erlang.nif_error(:nif_not_loaded)
  # Phase 3-B: 指定座標リストに敵をスポーンする NIF
  def spawn_enemies_at(_world, _kind, _positions), do: :erlang.nif_error(:nif_not_loaded)

  # I-2: 武器スロットを Elixir 側から毎フレーム注入する NIF（add_weapon の代替）
  # R-W2: slots: [{kind_id, level, cooldown_timer, precomputed_damage}] のリスト
  def set_weapon_slots(_world, _slots), do: :erlang.nif_error(:nif_not_loaded)

  # Elixir SSoT 移行: 衝突用スナップショット注入（毎フレーム on_nif_sync で呼ぶ）
  # snapshot: :none | {:alive, x, y, radius, damage_per_sec, invincible}
  def set_special_entity_snapshot(_world, _snapshot), do: :erlang.nif_error(:nif_not_loaded)

  # Phase R-3: spawn_elite_enemy を汎用化（エリートという概念を NIF 層から排除）
  def spawn_enemies_with_hp_multiplier(_world, _kind_id, _count, _hp_multiplier),
    do: :erlang.nif_error(:nif_not_loaded)

  # Phase 3-C: スコアポップアップを描画用バッファに追加する NIF
  # R-E1: lifetime は contents から注入（表示時間の SSoT）
  def add_score_popup(_world, _x, _y, _value, _lifetime), do: :erlang.nif_error(:nif_not_loaded)
  # Phase 3-B: Elixir 側のルールがアイテムドロップを制御するための NIF
  # kind: 0=Gem, 1=Potion, 2=Magnet
  def spawn_item(_world, _x, _y, _kind, _value), do: :erlang.nif_error(:nif_not_loaded)

  # entity_id: {:enemy, index}（ボス用は廃止・Elixir SSoT）
  def set_entity_hp(_world, _entity_id, _hp), do: :erlang.nif_error(:nif_not_loaded)

  # x/y は発射座標、vx/vy は速度ベクトル（正規化済み × speed）、kind は BULLET_KIND_* 定数
  def spawn_projectile(_world, _x, _y, _vx, _vy, _damage, _lifetime, _kind),
    do: :erlang.nif_error(:nif_not_loaded)

  def create_game_loop_control, do: :erlang.nif_error(:nif_not_loaded)
  def start_rust_game_loop(_world, _control, _pid), do: :erlang.nif_error(:nif_not_loaded)

  # Phase 3: XR 入力スレッド起動（VR 有効時のみ。xr フィーチャー無効時は nif_not_loaded）
  def spawn_xr_input_thread(_pid), do: :erlang.nif_error(:nif_not_loaded)

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
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_player_dead(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── Elixir SSoT 注入 NIF（毎フレーム呼ばれる）──────────────────────
  # PlayerState SSoT: hp と invincible_timer を毎フレーム注入
  def set_player_snapshot(_world, _hp, _invincible_timer),
    do: :erlang.nif_error(:nif_not_loaded)

  def set_player_position(_world, _x, _y), do: :erlang.nif_error(:nif_not_loaded)
  def set_elapsed_seconds(_world, _elapsed), do: :erlang.nif_error(:nif_not_loaded)

  # ── Phase 3-A: World パラメータ注入 NIF ──────────────────────────
  # ワールド生成後に一度だけ呼び出す。
  def set_world_size(_world, _width, _height), do: :erlang.nif_error(:nif_not_loaded)

  # R-C1: 物理定数注入。params: %{player_speed: 200, bullet_speed: 400, bullet_lifetime: 3.0} 等
  def set_world_params(_world, _params), do: :erlang.nif_error(:nif_not_loaded)

  # enemies: [{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, passes_obstacles}]
  # weapons: [{cooldown, damage, as_u8, name, bullet_table_or_nil}]
  # bosses:  [{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, special_interval}]
  # opts: P4-1: オプション。%{default_enemy_radius, default_particle_color, ...} でデフォルト値を上書き可能。nil の場合は Rust 定数を使用。
  def set_entity_params(_world, _enemies, _weapons, _bosses, _opts \\ nil),
    do: :erlang.nif_error(:nif_not_loaded)

  # R-P2: 敵接触の damage_this_frame。list: [{kind_id, damage}, ...] — 毎フレーム on_nif_sync で呼ぶ
  def set_enemy_damage_this_frame(_world, _list), do: :erlang.nif_error(:nif_not_loaded)

  # ── Push 型同期 NIF ────────────────────────────────────────────
  def push_tick(_world, _dx, _dy, _delta_ms), do: :erlang.nif_error(:nif_not_loaded)

  # ── Phase R-2: 描画用エンティティスナップショット ──────────────────
  # 戻り値: {player_x, player_y, frame_id, enemies, bullets, particles,
  #          items, obstacles, boss, score_popups}
  def get_render_entities(_world), do: :erlang.nif_error(:nif_not_loaded)

  # R-W1: get_weapon_upgrade_descs は削除。WeaponFormulas.weapon_upgrade_descs で Elixir 側完結。

  # ── 移行検証用（フェーズ0）───────────────────────────────────────
  def get_full_game_state(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── snapshot_heavy（明示操作時のみ）──────────────────────────────
  def get_save_snapshot(_world), do: :erlang.nif_error(:nif_not_loaded)
  def load_save_snapshot(_world, _snapshot), do: :erlang.nif_error(:nif_not_loaded)
  def debug_dump_world(_world), do: :erlang.nif_error(:nif_not_loaded)

  # ── Formula（コンテンツ数式エンジン）────────────────────────────────
  # bytecode: バイナリ形式のバイトコード
  # inputs: %{"name" => value} のマップ
  # store_values: Store の初期値 %{"key" => value}（Phase 2）
  # 戻り値: {:ok, {outputs, updated_store}} | {:error, reason, detail}
  def run_formula_bytecode(_bytecode, _inputs, _store_values),
    do: :erlang.nif_error(:nif_not_loaded)
end
