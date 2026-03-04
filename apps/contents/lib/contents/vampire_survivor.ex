defmodule Content.VampireSurvivor do
  @moduledoc """
  ヴァンパイアサバイバーのコンテンツ定義。

  エンジンは `components/0` が返すコンポーネントリストを順に呼び出す。
  各コンポーネントは `Core.Component` ビヘイビアを実装する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.VampireSurvivor.SpawnComponent,
      Content.VampireSurvivor.LevelComponent,
      Content.VampireSurvivor.BossComponent,
      Content.VampireSurvivor.RenderComponent
    ]
  end

  # ── シーン定義（エンジンが参照するシーン構成）────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [
      %{module: Content.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  def physics_scenes do
    [Content.VampireSurvivor.Scenes.Playing]
  end

  def playing_scene, do: Content.VampireSurvivor.Scenes.Playing
  def game_over_scene, do: Content.VampireSurvivor.Scenes.GameOver
  def level_up_scene, do: Content.VampireSurvivor.Scenes.LevelUp
  def boss_alert_scene, do: Content.VampireSurvivor.Scenes.BossAlert

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Vampire Survivor"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録（SpawnComponent に委譲）──────────

  defdelegate assets_path, to: Content.VampireSurvivor.SpawnComponent
  defdelegate entity_registry, to: Content.VampireSurvivor.SpawnComponent

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── レベルアップ・武器選択（LevelSystem / Playing シーンに委譲）──

  defdelegate generate_weapon_choices(weapon_levels), to: Content.VampireSurvivor.LevelSystem
  defdelegate apply_level_up(scene_state, choices), to: Content.VampireSurvivor.Scenes.Playing

  defdelegate apply_weapon_selected(scene_state, weapon),
    to: Content.VampireSurvivor.Scenes.Playing

  defdelegate apply_level_up_skipped(scene_state), to: Content.VampireSurvivor.Scenes.Playing

  # ── 報酬・スコア計算（EntityParams に委譲）──────────────────────

  defdelegate enemy_exp_reward(enemy_kind), to: Content.EntityParams
  defdelegate boss_exp_reward(boss_kind), to: Content.EntityParams
  defdelegate score_from_exp(exp), to: Content.EntityParams

  # ── ウェーブラベル（SpawnSystem に委譲）──────────────────────────

  defdelegate wave_label(elapsed_sec), to: Content.VampireSurvivor.SpawnSystem

  # ── シーン push 時の物理一時停止判定 ─────────────────────────────

  def pause_on_push?(mod) do
    mod == Content.VampireSurvivor.Scenes.LevelUp or
      mod == Content.VampireSurvivor.Scenes.BossAlert
  end
end
