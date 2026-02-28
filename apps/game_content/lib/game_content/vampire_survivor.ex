defmodule GameContent.VampireSurvivor do
  @moduledoc """
  ヴァンパイアサバイバーのコンテンツ定義。

  エンジンは `components/0` が返すコンポーネントリストを順に呼び出す。
  各コンポーネントは `GameEngine.Component` ビヘイビアを実装する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      GameContent.VampireSurvivor.SpawnComponent,
      GameContent.VampireSurvivor.LevelComponent,
      GameContent.VampireSurvivor.BossComponent,
    ]
  end

  # ── シーン定義（エンジンが参照するシーン構成）────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [
      %{module: GameContent.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  def physics_scenes do
    [GameContent.VampireSurvivor.Scenes.Playing]
  end

  def playing_scene, do: GameContent.VampireSurvivor.Scenes.Playing
  def game_over_scene, do: GameContent.VampireSurvivor.Scenes.GameOver
  def level_up_scene, do: GameContent.VampireSurvivor.Scenes.LevelUp
  def boss_alert_scene, do: GameContent.VampireSurvivor.Scenes.BossAlert

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Vampire Survivor"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録（SpawnComponent に委譲）──────────

  def assets_path, do: GameContent.VampireSurvivor.SpawnComponent.assets_path()
  def entity_registry, do: GameContent.VampireSurvivor.SpawnComponent.entity_registry()

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── レベルアップ・武器選択（Playing シーンに委譲）────────────────

  def generate_weapon_choices(weapon_levels) do
    GameContent.VampireSurvivor.LevelSystem.generate_weapon_choices(weapon_levels)
  end

  def apply_level_up(scene_state, choices) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up(scene_state, choices)
  end

  def apply_weapon_selected(scene_state, weapon) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_weapon_selected(scene_state, weapon)
  end

  def apply_level_up_skipped(scene_state) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up_skipped(scene_state)
  end

  # ── 報酬・スコア計算（EntityParams に委譲）──────────────────────

  def enemy_exp_reward(enemy_kind), do: GameContent.EntityParams.enemy_exp_reward(enemy_kind)
  def boss_exp_reward(boss_kind), do: GameContent.EntityParams.boss_exp_reward(boss_kind)
  def score_from_exp(exp), do: GameContent.EntityParams.score_from_exp(exp)

  # ── ウェーブラベル（SpawnSystem に委譲）──────────────────────────

  def wave_label(elapsed_sec) do
    GameContent.VampireSurvivor.SpawnSystem.wave_label(elapsed_sec)
  end
end
