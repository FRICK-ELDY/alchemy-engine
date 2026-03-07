defmodule Core.ContentBehaviour do
  @moduledoc """
  コンテンツモジュールが実装すべきビヘイビア。

  必須コールバックはすべてのコンテンツで実装が必要。
  オプショナルコールバックは武器・ボスの概念を持つコンテンツのみ実装する。

  ## 設計原則

  エンジンはコンテンツを知らない。`GameEvents` はこのビヘイビアを通じて
  コンテンツと通信し、`function_exported?/3` による分岐を排除する。
  """

  @type scene_module :: module()
  @type scene_state :: map()
  @type weapon :: atom()
  @type boss_kind :: non_neg_integer()
  @type exp :: non_neg_integer()

  # ── 必須コールバック ───────────────────────────────────────────────

  @callback components() :: [module()]

  @doc """
  そのルームのシーンスタック（またはフロー管理）の pid を返す。

  `Process.whereis/1` 使用時は pid() | nil となりうる。
  nil は SceneManager 未登録等の起動前状態を表し、
  Phase 3 以降で呼び出し元が nil を適切に扱う必要がある。
  room_id は将来のマルチルーム対応で使用する予定。
  """
  @callback flow_runner(room_id :: term()) :: pid() | nil

  @doc """
  そのルームのイベントハンドラ（GameEvents）の pid を返す。

  InputHandler・Network 等がイベント送信先を取得する際に使用する。
  nil は GameEvents 未起動状態を表す。
  """
  @callback event_handler(room_id :: term()) :: pid() | nil

  @callback initial_scenes() :: [%{module: scene_module(), init_arg: map()}]
  @callback physics_scenes() :: [scene_module()]
  @callback playing_scene() :: scene_module()
  @callback game_over_scene() :: scene_module()
  @callback entity_registry() :: map()
  @callback enemy_exp_reward(kind_id :: non_neg_integer()) :: exp()
  @callback score_from_exp(exp()) :: non_neg_integer()
  @callback wave_label(elapsed_sec :: float()) :: String.t()
  @callback context_defaults() :: map()

  # ── オプショナルコールバック（武器・ボスの概念を持つコンテンツのみ）──

  @doc "レベルアップシーンモジュールを返す（武器選択 UI を持つコンテンツのみ実装）"
  @callback level_up_scene() :: scene_module()

  @doc "ボスアラートシーンモジュールを返す（ボスの概念を持つコンテンツのみ実装）"
  @callback boss_alert_scene() :: scene_module()

  @doc "ボス撃破時の EXP 報酬を返す（ボスの概念を持つコンテンツのみ実装）"
  @callback boss_exp_reward(boss_kind()) :: exp()

  @doc "レベルアップ時の武器選択肢を生成する（武器選択 UI を持つコンテンツのみ実装）"
  @callback generate_weapon_choices(weapon_levels :: map()) :: [weapon()]

  @doc "武器選択適用（武器選択 UI を持つコンテンツのみ実装）"
  @callback apply_weapon_selected(scene_state(), weapon()) :: scene_state()

  @doc "レベルアップスキップ適用（武器選択 UI を持つコンテンツのみ実装）"
  @callback apply_level_up_skipped(scene_state()) :: scene_state()

  @doc """
  シーンを push するときに物理演算を一時停止すべきかどうかを返す。

  デフォルト実装（`false` を返す）を提供するため、
  ボス/レベルアップシーンで一時停止が必要なコンテンツのみ実装する。
  """
  @callback pause_on_push?(scene_module()) :: boolean()

  @doc """
  ルーム用の SceneStack の Superviser.child_spec/0 を返す。

  ルーム起動時に content が自分の SceneStack を起動する際に使用する。
  room_id はマルチルーム対応用（単一ルーム時は任意の値でよい）。
  """
  @callback scene_stack_spec(room_id :: term()) :: Supervisor.child_spec()

  @doc """
  ローカルユーザー入力を提供するモジュールを返す。

  - オプショナル。content が未実装の場合、Contents.ComponentList が
    Contents.LocalUserComponent をデフォルトとして使用する。
  - 実装時: 返した `module` を使用。`nil` を返した場合もデフォルトを使用。
  - 指定モジュールの `get_move_vector/1` を呼んで player_input を取得。
    raw_key / raw_mouse_motion / focus_lost はコンポーネントに dispatch され、
    当該モジュールが on_event で処理する。
  """
  @callback local_user_input_module() :: module() | nil

  @optional_callbacks [
    level_up_scene: 0,
    boss_alert_scene: 0,
    boss_exp_reward: 1,
    generate_weapon_choices: 1,
    apply_weapon_selected: 2,
    apply_level_up_skipped: 1,
    pause_on_push?: 1,
    scene_stack_spec: 1,
    local_user_input_module: 0
  ]
end
