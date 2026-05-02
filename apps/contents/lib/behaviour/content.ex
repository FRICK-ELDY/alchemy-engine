defmodule Contents.Behaviour.Content do
  @moduledoc """
  コンテンツモジュールが実装すべきビヘイビア。

  契約の定義は Contents が保持する。core はコンパイル時には contents に依存せず、
  実行時に `Core.Config.current/0` で得た content モジュール（本 Behaviour を実装したモジュール）を
  参照し、その関数（initial_scenes/0, playing_scene/0 等）を呼び出す。

  必須コールバックはすべてのコンテンツで実装が必要。
  オプショナルコールバックは、武器・ボス・敵カタログ・EXP などの概念を使うコンテンツのみ実装する。

  ## 設計原則

  エンジンはコンテンツを知らない。イベントハンドラ（`Contents.Events.Game`。旧名 GameEvents）は
  このビヘイビアを通じてコンテンツと通信し、`function_exported?/3` による分岐を排除する。
  """

  @type scene_module :: module()
  @type scene_state :: map()
  @type weapon :: atom()
  @type boss_kind :: non_neg_integer()
  @type exp :: non_neg_integer()

  @doc """
  シーン種別を表す atom。コンテンツは必要な種別のみ実装すればよい。

  推奨シーン種別の例: `:playing`, `:title`, `:game_over`, `:level_up`,
  `:boss_alert`, `:stage_clear`, `:ending`
  """
  @type scene_type :: atom()

  # ── 必須コールバック ───────────────────────────────────────────────

  @callback components() :: [module()]

  @doc """
  そのルームのシーンスタック（`Contents.Scenes.Stack`）の pid を返す。

  `Process.whereis(Contents.Scenes.Stack)` 使用時は pid() | nil となりうる。
  nil はシーンスタック未起動等の起動前状態を表し、
  Phase 3 以降で呼び出し元が nil を適切に扱う必要がある。
  room_id は将来のマルチルーム対応で使用する予定。
  """
  @callback flow_runner(room_id :: term()) :: pid() | nil

  @doc """
  シーン種別ごとの初期化。返却 state には、新規・将来コンテンツでは origin（空間の原点）を持ち、
  必要に応じて着地点参照（landing_object）・トップレベル子（children）を含めることを推奨する。
  `Contents.Behaviour.Scenes` の init/1 の @doc も参照。
  """
  @callback scene_init(scene_type(), init_arg :: term()) :: {:ok, state :: term()}

  @doc """
  シーン種別ごとの update。戻り値は SceneBehaviour の update と同様（{:continue, state} または {:transition, ...}）。
  """
  @callback scene_update(scene_type(), context :: map(), state :: term()) ::
              {:continue, state :: term()}
              | {:continue, state :: term(), opts :: map()}
              | {:transition, :pop, state :: term()}
              | {:transition, :pop, state :: term(), opts :: map()}
              | {:transition, {:push, scene_type(), init_arg :: term()}, state :: term()}
              | {:transition, {:push, scene_type(), init_arg :: term()}, state :: term(),
                 opts :: map()}
              | {:transition, {:replace, scene_type(), init_arg :: term()}, state :: term()}
              | {:transition, {:replace, scene_type(), init_arg :: term()}, state :: term(),
                 opts :: map()}

  @doc """
  シーン種別ごとの描画種別（例: :playing, :title）。
  """
  @callback scene_render_type(scene_type()) :: atom()

  @doc """
  そのルームのイベントハンドラ（`Contents.Events.Game`。旧名 GameEvents）の pid を返す。

  InputHandler・Network 等がイベント送信先を取得する際に使用する。
  nil はイベントハンドラ未起動状態を表す。
  """
  @callback event_handler(room_id :: term()) :: pid() | nil

  @callback initial_scenes() :: [%{scene_type: scene_type(), init_arg: map()}]
  @callback physics_scenes() :: [scene_type()]
  @callback playing_scene() :: scene_type()
  @callback game_over_scene() :: scene_type()
  @callback wave_label(elapsed_sec :: float()) :: String.t()
  @callback context_defaults() :: map()

  # ── オプショナルコールバック ───────────────────────────────────────

  @doc """
  敵・武器の kind_id とパラメータの対応表（診断・将来の同期用）。

  EXP や敵種別テーブルを使わないコンテンツは未実装でよい。
  """
  @callback entity_registry() :: map()

  @doc "敵種別ごとの撃破 EXP。EXP を使わないコンテンツは未実装でよい。"
  @callback enemy_exp_reward(kind_id :: non_neg_integer()) :: exp()

  @doc "累積 EXP から表示スコアへの換算。EXP を使わないコンテンツは未実装でよい。"
  @callback score_from_exp(exp()) :: non_neg_integer()

  @doc "レベルアップシーン種別を返す（武器選択 UI を持つコンテンツのみ実装）"
  @callback level_up_scene() :: scene_type()

  @doc "ボスアラートシーン種別を返す（ボスの概念を持つコンテンツのみ実装）"
  @callback boss_alert_scene() :: scene_type()

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
  @callback pause_on_push?(scene_type()) :: boolean()

  @doc """
  ルーム用のシーンスタック（`Contents.Scenes.Stack`）の Superviser.child_spec/0 を返す。

  ルーム起動時に content が自分のシーンスタックを起動する際に使用する。
  room_id はマルチルーム対応用（単一ルーム時は任意の値でよい）。
  """
  @callback scene_stack_spec(room_id :: term()) :: Supervisor.child_spec()

  @doc """
  ローカルユーザー入力を提供するモジュールを返す。

  - オプショナル。content が未実装の場合、Contents.ComponentList が
    Contents.LocalUserComponent をデフォルトとして使用する。
  - 実装時: 返した `module` を使用。`nil` を返した場合もデフォルトを使用。
  - `{:move_input, dx, dy}` 等は `Contents.Events.Game` がコンポーネントへ dispatch する。
    必要なら各モジュールの `get_move_vector/1` や ETS をコンポーネント側から参照する。
  """
  @callback local_user_input_module() :: module() | nil

  @doc """
  終了要求（`__quit__` UI アクション等）が届いたときに呼ばれる。
  セーブ、確認ダイアログ等を行ってから `System.stop/1` を呼ぶ想定。
  未実装時は Game が `System.stop(0)` をデフォルトで実行する。
  """
  @callback on_quit_requested() :: :ok

  @doc """
  描画フレームを組み立てる。Rendering.Render が呼ぶ。

  playing_state は現在の playing シーンの state。context は on_nif_sync の context。
  context には :current_scene が含まれる（現在表示中のシーン種別）。
  戻り値は `Content.FrameEncoder.encode_frame/6`（描画用 3 要素）に渡す形式の
  `{commands, camera, ui}`。未実装の Content では Render が描画をスキップする。
  """
  @callback build_frame(playing_state :: map(), context :: map()) ::
              {commands :: list(), camera :: tuple(), ui :: tuple()}

  @doc """
  Zenoh 向け `RenderFrame` の `AudioFrame` に載せるキュー（識別子文字列列）。

  未実装時は `Rendering.Render` が空リストを渡す。非空を返すコンテンツは、対となる
  `after_zenoh_audio_cues_sent/1` を実装して送信後の状態更新（例: pending のクリア）を行うこと。
  """
  @callback zenoh_audio_cues(playing_state :: map()) :: [String.t()]

  @doc """
  `zenoh_audio_cues/1` が非空だったフレームで、`encode_frame` 送信の直後に呼ばれる。

  `runner` は `flow_runner/1` と同じ（`nil` のこともある）。未実装時は何もしない。
  """
  @callback after_zenoh_audio_cues_sent(runner :: pid() | nil) :: :ok

  @doc """
  メッシュ定義のリストを返す。Rendering.Render が `encode_frame` の mesh 用引数に渡す。
  未実装の Content では [] を使用する。
  """
  @callback mesh_definitions() :: list()

  @doc """
  ワールドサイズを {width, height} で返す。将来の物理・ワールド境界用のオプション。
  未実装の Content ではデフォルト挙動を使う。
  """
  @callback world_size() :: {width :: float(), height :: float()}

  @optional_callbacks [
    entity_registry: 0,
    enemy_exp_reward: 1,
    score_from_exp: 1,
    build_frame: 2,
    zenoh_audio_cues: 1,
    after_zenoh_audio_cues_sent: 1,
    mesh_definitions: 0,
    world_size: 0,
    on_quit_requested: 0,
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
