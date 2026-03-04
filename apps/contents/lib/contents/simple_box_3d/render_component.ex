defmodule Content.SimpleBox3D.RenderComponent do
  @moduledoc """
  毎フレーム3D DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  Phase R-6: SimpleBox3D コンテンツの描画担当。
  Elixir 側のシーン state（プレイヤー・敵の3D座標）から DrawCommand を組み立て、
  Camera3D と共に RenderFrameBuffer に書き込む。

  ## 描画内容
  - `DrawCommand::Skybox` — 空色グラデーション背景
  - `DrawCommand::GridPlane` — XZ 平面グリッド地面
  - `DrawCommand::Box3D` — プレイヤー（青）と敵（赤）
  """
  @behaviour Core.Component

  # ボックスの半サイズ
  @half_size 0.5

  # カメラ設定（斜め上から俯瞰）
  @camera_eye {0.0, 18.0, 14.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 100.0

  # 色定義
  @color_player {0.2, 0.4, 0.9, 1.0}
  @color_enemy {0.9, 0.2, 0.2, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}

  # グリッドパラメータ
  @grid_size 20.0
  @grid_divisions 20

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()

    current_scene =
      case Core.SceneManager.current() do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    playing_state = Core.SceneManager.get_scene_state(content.playing_scene()) || %{}

    commands = build_commands(playing_state)
    camera = build_camera()
    ui = build_ui(current_scene, content)

    Core.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      ui,
      :no_change
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(scene_state) do
    player = Map.get(scene_state, :player, {0.0, 0.0, 0.0})
    enemies = Map.get(scene_state, :enemies, [])

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {pr, pg, pb, pa} = @color_player
    {er, eg, eb, ea} = @color_enemy

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_cmd = {:grid_plane, @grid_size, @grid_divisions, {grid_r, grid_g, grid_b, grid_a}}

    {px, py, pz} = player

    player_cmd =
      {:box_3d, px, py + @half_size, pz, @half_size, @half_size, {@half_size, pr, pg, pb, pa}}

    enemy_cmds =
      Enum.map(enemies, fn {ex, ey, ez} ->
        {:box_3d, ex, ey + @half_size, ez, @half_size, @half_size, {@half_size, er, eg, eb, ea}}
      end)

    [skybox_cmd, grid_cmd, player_cmd | enemy_cmds]
  end

  # ── カメラ組み立て ─────────────────────────────────────────────────

  defp build_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  # ── UiCanvas 組み立て ─────────────────────────────────────────────

  defp build_ui(current_scene, content) do
    nodes =
      if current_scene == content.game_over_scene() do
        [
          {:node, {:center, {0.0, 0.0}, :wrap},
           {:rect, {0.08, 0.02, 0.02, 0.92}, 16.0, {{0.78, 0.24, 0.24, 1.0}, 2.0}},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 8.0, {50.0, 35.0, 50.0, 35.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "GAME OVER", {1.0, 0.31, 0.31, 1.0}, 40.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:button, "  RETRY  ", "__retry__", {0.63, 0.16, 0.16, 1.0}, 160.0, 44.0}, []}
              ]}
           ]}
        ]
      else
        []
      end

    {:canvas, nodes}
  end
end
