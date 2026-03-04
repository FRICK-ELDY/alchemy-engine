defmodule Content.CanvasTest do
  @moduledoc """
  CanvasUI デバッグコンテンツ。

  1人称視点の自由移動・ESCキーによる HUD 開閉・ワールド空間内の Canvas パネルを通じて、
  UIシステムの各機能を網羅的に確認できる環境を提供する。

  ## 検証機能
  - HUD Canvas（スクリーン空間）: ESC キーで表示/非表示を切り替え
  - HUD 内ボタン: 押下でウィンドウを閉じる（`__quit__` アクション）
  - ワールド Canvas（3D 空間内）: 3D 座標に固定されたテキストパネルを複数配置
  - レイアウト: `vertical_layout` / `rect` / `world_text` の組み合わせ

  ## 設計方針
  - Elixir = SSoT: カメラ姿勢（位置・Yaw・Pitch）・HUD 表示フラグを Elixir 側で管理
  - Rust = 演算層: 描画・入力受信のみ担当
  - 物理エンジン（physics）は使用しない
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.CanvasTest.InputComponent,
      Content.CanvasTest.RenderComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.SceneStack)

  def initial_scenes do
    [%{module: Content.CanvasTest.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    []
  end

  def playing_scene, do: Content.CanvasTest.Scenes.Playing

  # CanvasTest にゲームオーバーの概念はないため、ContentBehaviour の契約を満たす目的で
  # playing_scene と同じシーンを返す。
  def game_over_scene, do: Content.CanvasTest.Scenes.Playing

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Canvas Test"
  def version, do: "0.1.0"

  # ── アセット（共通 LocalAssets を参照）───────────────────────────────

  def assets_path, do: ""

  # ── エンティティレジストリ（CanvasTest はエネミー・武器の概念なし）──

  def entity_registry, do: %{weapons: %{}, enemies: %{}}

  def enemy_exp_reward(_kind_id), do: 0

  def score_from_exp(_exp), do: 0

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "CanvasTest #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
