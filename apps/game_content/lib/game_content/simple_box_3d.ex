defmodule GameContent.SimpleBox3D do
  @moduledoc """
  シンプルな3Dゲームコンテンツ。

  Phase R-6: 3Dレンダリングパイプラインの動作検証用コンテンツ。

  - 青いボックス = プレイヤー（WASD移動）
  - 赤いボックス = 敵（プレイヤーを追跡）
  - グリッド地面
  - スカイボックス（空色グラデーション）
  - 固定カメラ（斜め上から俯瞰）

  Rust 側の物理エンジン（ECS）を使用せず、Elixir 側で3D座標を管理する。
  `push_render_frame` に `DrawCommand::Box3D` / `GridPlane` / `Skybox` を送ることで
  3Dパイプラインの動作を実証する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      GameContent.SimpleBox3D.SpawnComponent,
      GameContent.SimpleBox3D.InputComponent,
      GameContent.SimpleBox3D.RenderComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def initial_scenes do
    [%{module: GameContent.SimpleBox3D.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    [GameContent.SimpleBox3D.Scenes.Playing]
  end

  def playing_scene, do: GameContent.SimpleBox3D.Scenes.Playing
  def game_over_scene, do: GameContent.SimpleBox3D.Scenes.GameOver

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Simple Box 3D"
  def version, do: "0.1.0"

  # ── アセット（3Dコンテンツはアトラス不要だが、インターフェースを合わせる）──

  def assets_path, do: nil

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "SimpleBox3D #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
