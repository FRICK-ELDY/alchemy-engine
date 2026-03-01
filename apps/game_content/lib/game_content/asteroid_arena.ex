defmodule GameContent.AsteroidArena do
  @moduledoc """
  AsteroidArena のコンテンツ定義。

  武器・ボス・レベルアップの概念を持たないシンプルなシューターコンテンツ。
  `level_up_scene/0`・`boss_alert_scene/0` を実装しないことで、
  エンジンコアがこれらの概念を持たなくても動作することを実証する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      GameContent.AsteroidArena.SpawnComponent,
      GameContent.AsteroidArena.SplitComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [%{module: GameContent.AsteroidArena.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    [GameContent.AsteroidArena.Scenes.Playing]
  end

  def playing_scene, do: GameContent.AsteroidArena.Scenes.Playing
  def game_over_scene, do: GameContent.AsteroidArena.Scenes.GameOver

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Asteroid Arena"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録 ────────────────────────────────────

  defdelegate assets_path, to: GameContent.AsteroidArena.SpawnComponent
  defdelegate entity_registry, to: GameContent.AsteroidArena.SpawnComponent

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── 報酬・スコア計算 ──────────────────────────────────────────────

  defdelegate enemy_exp_reward(enemy_kind),
    to: GameContent.AsteroidArena.SpawnSystem,
    as: :exp_reward

  defdelegate score_from_exp(exp), to: GameContent.AsteroidArena.SpawnSystem

  # ── ウェーブラベル ────────────────────────────────────────────────

  defdelegate wave_label(elapsed_sec), to: GameContent.AsteroidArena.SpawnSystem
end
