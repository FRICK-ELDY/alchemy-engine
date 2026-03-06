defmodule Core.NifBridge.Behaviour do
  @moduledoc """
  `Core.NifBridge` の Behaviour 定義。

  テスト時に `Mox` でモック化するために使用する。
  本番コードは `Core.NifBridge` が直接 NIF を呼び出すため、
  このビヘイビアを `@behaviour` として宣言する必要はない。
  """

  # ── Phase R-2: push_render_frame 引数の型エイリアス ──────────────
  # sprite_raw が推奨。player_sprite / item はレガシー（SpriteRaw で代用可能）。
  @type draw_command ::
          {:sprite_raw, float(), float(), float(), float(),
           {{float(), float()}, {float(), float()}, {float(), float(), float(), float()}}}
          | {:player_sprite, float(), float(), non_neg_integer()}
          | {:sprite, float(), float(), non_neg_integer(), non_neg_integer()}
          | {:particle, float(), float(), float(), float(), float(), {float(), float()}}
          | {:item, float(), float(), non_neg_integer()}
          | {:obstacle, float(), float(), float(), non_neg_integer()}

  @type camera_params :: {:camera_2d, float(), float()}

  @type hud_data ::
          {{float(), float(), non_neg_integer(), float(), non_neg_integer(), non_neg_integer(),
            non_neg_integer()}, {non_neg_integer(), non_neg_integer(), float(), boolean()},
           {[String.t()], [[String.t()]], [{String.t(), non_neg_integer()}]},
           {float(), non_neg_integer(), :none | {String.t(), float(), float()}, atom(), float(),
            [{float(), float(), non_neg_integer(), float()}], non_neg_integer()}}

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
  # Phase R-3: spawn_boss を汎用化
  @callback spawn_special_entity(reference(), non_neg_integer()) :: :ok
  # Phase R-3: spawn_elite_enemy を汎用化
  @callback spawn_enemies_with_hp_multiplier(
              reference(),
              non_neg_integer(),
              non_neg_integer(),
              float()
            ) :: :ok
  @callback add_score_popup(reference(), float(), float(), non_neg_integer(), float()) :: :ok
  @callback spawn_item(reference(), float(), float(), non_neg_integer(), non_neg_integer()) :: :ok
  # Phase R-3: 汎用エンティティ操作 NIF
  @callback set_entity_velocity(reference(), atom(), float(), float()) :: :ok
  @callback set_entity_flag(reference(), atom(), atom(), boolean()) :: :ok
  @callback set_entity_hp(reference(), term(), float()) :: :ok
  # x, y, vx, vy, damage, lifetime, kind の順。
  # is_player は常に false 固定（プレイヤー弾は weapon システム経由）のため引数に含まない。
  @callback spawn_projectile(
              reference(),
              float(),
              float(),
              float(),
              float(),
              integer(),
              float(),
              non_neg_integer()
            ) :: :ok
  @callback create_game_loop_control() :: reference()
  @callback start_rust_game_loop(reference(), reference(), pid()) :: :ok
  @callback create_render_frame_buffer() :: reference()
  # atlas_path: アトラス PNG のファイルパス。Rust 側でロードし、存在しない場合は埋め込みフォールバックを使用する。
  @callback start_render_thread(reference(), reference(), pid(), String.t(), String.t()) :: :ok
  @callback push_render_frame(reference(), [draw_command()], camera_params(), hud_data()) :: :ok
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
  # Phase R-3: phase_timer は Elixir 側プロセス辞書で管理するため参照のみ（書き込みNIFなし）
  @callback get_boss_state(reference()) ::
              {:alive, float(), float(), float(), float(), float()} | :none
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  @callback is_player_dead(reference()) :: boolean()

  # ── Elixir SSoT 注入 NIF ─────────────────────────────────────────
  @callback set_player_snapshot(reference(), float(), float()) :: :ok
  @callback set_player_position(reference(), float(), float()) :: :ok
  @callback set_elapsed_seconds(reference(), float()) :: :ok

  # ── Phase 3-A: World パラメータ注入 NIF ──────────────────────────
  @callback set_world_size(reference(), float(), float()) :: :ok
  @callback set_world_params(reference(), map()) :: :ok
  @callback set_entity_params(reference(), list(), list(), list()) :: :ok

  # ── Push 型同期 NIF ────────────────────────────────────────────
  @callback push_tick(reference(), float(), float(), non_neg_integer()) :: :ok

  # ── Phase R-2: 描画用エンティティスナップショット ──────────────────
  @callback get_render_entities(reference()) :: tuple()

  # ── 移行検証用 ───────────────────────────────────────────────────
  @callback get_full_game_state(reference()) :: map()

  # ── snapshot_heavy ────────────────────────────────────────────────
  # 戻り値・第2引数は Rust SaveSnapshot に対応する map（atom キー: player_hp, player_x 等）
  @callback get_save_snapshot(reference()) :: map()
  @callback load_save_snapshot(reference(), map()) :: :ok
  @callback debug_dump_world(reference()) :: binary()
end
