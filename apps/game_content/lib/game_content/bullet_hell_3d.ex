defmodule GameContent.BulletHell3D do
  @moduledoc """
  3D 弾幕避けゲームコンテンツ。

  SimpleBox3D の3Dパイプラインを基盤に、弾幕避けゲームプレイを追加する。
  Elixir 側で3D座標・弾・敵を管理し、Rust 物理エンジンは使用しない。

  ## ゲームルール
  - プレイヤー（青ボックス）は WASD で XZ 平面上を移動
  - 敵（赤ボックス）がフィールド外周から出現し、プレイヤーに向かって直進
  - 敵が定期的にプレイヤー方向へ弾（黄ボックス）を発射
  - 弾または敵に当たると HP -1（HP = 3）
  - HP が 0 になるとゲームオーバー
  - 時間経過とともに敵数・発射間隔がスケールアップ
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      GameContent.BulletHell3D.SpawnComponent,
      GameContent.BulletHell3D.InputComponent,
      GameContent.BulletHell3D.BulletComponent,
      GameContent.BulletHell3D.DamageComponent,
      GameContent.BulletHell3D.RenderComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [%{module: GameContent.BulletHell3D.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    [GameContent.BulletHell3D.Scenes.Playing]
  end

  def playing_scene, do: GameContent.BulletHell3D.Scenes.Playing
  def game_over_scene, do: GameContent.BulletHell3D.Scenes.GameOver

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Bullet Hell 3D"
  def version, do: "0.1.0"

  # ── アセット（3Dコンテンツはアトラス不要）────────────────────────

  def assets_path, do: nil

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "BulletHell3D #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
