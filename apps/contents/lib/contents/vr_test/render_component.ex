defmodule Content.VRTest.RenderComponent do
  @moduledoc """
  VRTest の描画コンポーネント。

  Phase A: camera_yaw / camera_pitch から1人称カメラを組み立て、
  マウスで見回せる3D空間を描画する。
  """
  @behaviour Core.Component

  @half_size 0.5
  @camera_eye_height 1.7
  @camera_fov 75.0
  @camera_near 0.1
  @camera_far 100.0

  @color_player {0.2, 0.4, 0.9, 1.0}
  @color_enemy {0.9, 0.2, 0.2, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}

  @grid_size 20.0
  @grid_divisions 20

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    current_scene =
      case runner && Contents.SceneStack.current(runner) do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    commands = build_commands(playing_state)
    camera = build_camera(playing_state)
    ui = build_ui(current_scene, content)
    cursor_grab = Map.get(playing_state, :cursor_grab_request, :no_change)

    Core.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      ui,
      cursor_grab
    )

    if cursor_grab != :no_change and runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.VRTest.Scenes.Playing,
        &apply_cursor_grab_sync(&1, cursor_grab)
      )
    end

    :ok
  end

  defp apply_cursor_grab_sync(state, cursor_grab) do
    if state.cursor_grab_request == cursor_grab do
      new_grabbed = cursor_grab == :grab

      state
      |> Map.put(:cursor_grab_request, :no_change)
      |> Map.put(:cursor_grabbed, new_grabbed)
    else
      state
    end
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

  # ── カメラ組み立て（yaw/pitch から1人称視点）───────────────────────

  defp build_camera(scene_state) do
    {px, _py, pz} = Map.get(scene_state, :player, {0.0, 0.0, 0.0})
    yaw = Map.get(scene_state, :camera_yaw, 0.0)
    pitch = Map.get(scene_state, :camera_pitch, 0.0)

    eye_x = px
    eye_y = @camera_eye_height
    eye_z = pz

    # 前方ベクトル: yaw=0 で -Z 方向、pitch で上下
    cos_p = :math.cos(pitch)
    cos_y = :math.cos(yaw)
    sin_y = :math.sin(yaw)
    sin_p = :math.sin(pitch)

    fwd_x = cos_p * sin_y
    fwd_y = sin_p
    fwd_z = -cos_p * cos_y

    target_x = eye_x + fwd_x
    target_y = eye_y + fwd_y
    target_z = eye_z + fwd_z

    {:camera_3d, {eye_x, eye_y, eye_z}, {target_x, target_y, target_z}, {0.0, 1.0, 0.0},
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
