defmodule Content.VRTest do
  @moduledoc """
  VR 動作検証用コンテンツ。

  Phase A: デスクトップ上で3D空間を見渡す。
  - マウスドラッグでカメラ回転（周囲を見回せる）
  - 青いボックス = プレイヤー
  - 赤いボックス = 敵
  - グリッド地面・スカイボックス

  Phase B 以降で OpenXR head_pose をカメラに反映する予定。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.VRTest.SpawnComponent,
      Content.VRTest.InputComponent,
      Content.VRTest.RenderComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [%{module: Content.VRTest.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    [Content.VRTest.Scenes.Playing]
  end

  def playing_scene, do: Content.VRTest.Scenes.Playing
  def game_over_scene, do: Content.VRTest.Scenes.GameOver

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "VR Test"
  def version, do: "0.1.0"

  # ── アセット（共通 LocalAssets を参照）───────────────────────────────

  def assets_path, do: ""

  # ── コンテキストデフォルト ──────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）────────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "VRTest #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
