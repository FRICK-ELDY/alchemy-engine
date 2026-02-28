defmodule GameEngine.ContentBehaviour do
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

  @callback components()       :: [module()]
  @callback initial_scenes()   :: [%{module: scene_module(), init_arg: map()}]
  @callback physics_scenes()   :: [scene_module()]
  @callback playing_scene()    :: scene_module()
  @callback game_over_scene()  :: scene_module()
  @callback entity_registry()  :: map()
  @callback enemy_exp_reward(kind_id :: non_neg_integer()) :: exp()
  @callback score_from_exp(exp()) :: non_neg_integer()
  @callback wave_label(elapsed_sec :: float()) :: String.t()
  @callback context_defaults() :: map()

  # ── オプショナルコールバック（武器・ボスの概念を持つコンテンツのみ）──

  @doc "レベルアップシーンモジュールを返す（武器選択 UI を持つコンテンツのみ実装）"
  @callback level_up_scene()   :: scene_module()

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

  @optional_callbacks [
    level_up_scene: 0,
    boss_alert_scene: 0,
    boss_exp_reward: 1,
    generate_weapon_choices: 1,
    apply_weapon_selected: 2,
    apply_level_up_skipped: 1,
    pause_on_push?: 1,
  ]
end
