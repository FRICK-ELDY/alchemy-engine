defmodule Content.RollingBall.RenderComponent do
  alias Content.MessagePackEncoder
  alias Content.RollingBall.MeshDef
  alias Contents.FrameBroadcaster
  alias Contents.Scenes.Stack, as: SceneStack

  @moduledoc """
  毎フレーム3D DrawCommand リストを組み立てて FrameBroadcaster.put で Zenoh へ配信するコンポーネント。

  ## 描画内容
  - `DrawCommand::Skybox` — 昼空グラデーション背景
  - `DrawCommand::Box3D` — フロアタイル（グレー）、ボール（白・大）、障害物（赤）、ゴール（緑・高い柱）
  """
  @behaviour Core.Component

  # カメラ設定（斜め上から俯瞰）
  @camera_eye {0.0, 28.0, 22.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 150.0

  # 色定義
  @color_sky_top {0.55, 0.15, 0.10, 1.0}
  @color_sky_bottom {1.0, 0.55, 0.15, 1.0}
  @color_floor {0.55, 0.55, 0.60, 1.0}
  @color_ball {1.0, 1.0, 1.0, 1.0}
  @color_goal {0.1, 0.95, 0.3, 1.0}
  @color_obstacle {0.95, 0.15, 0.15, 1.0}
  @color_moving_obstacle {1.0, 0.55, 0.05, 1.0}

  @tile_half_xz 0.98
  @tile_half_y 0.08
  @ball_half 0.55
  @goal_half_xz 0.7
  @goal_half_y 1.0
  @obstacle_half 0.65

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    # Stack.current は %{scene_type: atom(), state: term()} を返す。scene_type で現在シーンを識別する。
    current_scene =
      case runner && SceneStack.current(runner) do
        {:ok, %{scene_type: st}} -> st
        _ -> content.playing_scene()
      end

    playing_state =
      (runner && SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    commands = build_commands(playing_state, current_scene)
    camera = build_camera()
    ui = build_ui(playing_state, current_scene, content)

    mesh_defs = MeshDef.definitions()
    frame_binary = MessagePackEncoder.encode_frame(commands, camera, ui, mesh_defs)
    FrameBroadcaster.put(context.room_id, frame_binary)

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(scene_state, current_scene) do
    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    title_scenes = [:title, :ending]

    if current_scene in title_scenes do
      [skybox_cmd]
    else
      floor_cmds = build_floor_cmds(scene_state)
      goal_cmds = build_goal_cmds(scene_state)
      obstacle_cmds = build_obstacle_cmds(scene_state)
      moving_obstacle_cmds = build_moving_obstacle_cmds(scene_state)
      ball_cmd = build_ball_cmd(scene_state)

      [skybox_cmd | floor_cmds] ++
        goal_cmds ++ obstacle_cmds ++ moving_obstacle_cmds ++ [ball_cmd]
    end
  end

  defp build_floor_cmds(scene_state) do
    floor_tiles = Map.get(scene_state, :floor_tiles, [])
    {fr, fg, fb, fa} = @color_floor

    Enum.map(floor_tiles, fn {x, z} ->
      {:box_3d, x, @tile_half_y, z, @tile_half_xz, @tile_half_y, {@tile_half_xz, fr, fg, fb, fa}}
    end)
  end

  defp build_goal_cmds(scene_state) do
    case Map.get(scene_state, :goal_pos) do
      nil ->
        []

      {gx, gz} ->
        {gr, gg, gb, ga} = @color_goal

        [
          {:box_3d, gx, @goal_half_y, gz, @goal_half_xz, @goal_half_y,
           {@goal_half_xz, gr, gg, gb, ga}}
        ]
    end
  end

  defp build_obstacle_cmds(scene_state) do
    obstacles = Map.get(scene_state, :obstacles, [])
    {r, g, b, a} = @color_obstacle

    Enum.map(obstacles, fn {x, z} ->
      {:box_3d, x, @obstacle_half, z, @obstacle_half, @obstacle_half,
       {@obstacle_half, r, g, b, a}}
    end)
  end

  defp build_moving_obstacle_cmds(scene_state) do
    moving = Map.get(scene_state, :moving_obstacles, [])
    {r, g, b, a} = @color_moving_obstacle

    Enum.map(moving, fn %{x: x, z: z} ->
      {:box_3d, x, @obstacle_half, z, @obstacle_half, @obstacle_half,
       {@obstacle_half, r, g, b, a}}
    end)
  end

  defp build_ball_cmd(scene_state) do
    default_y = @tile_half_y * 2 + @ball_half
    {bx, by, bz} = Map.get(scene_state, :ball, {0.0, default_y, 0.0})
    {r, g, b, a} = @color_ball
    {:box_3d, bx, by, bz, @ball_half, @ball_half, {@ball_half, r, g, b, a}}
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

  defp build_ui(playing_state, current_scene, content) do
    stage = Map.get(playing_state, :stage, 1)
    retries_left = Map.get(playing_state, :retries_left, 3)

    nodes =
      cond do
        current_scene == :title ->
          [build_title_panel()]

        current_scene == :stage_clear ->
          [build_stage_clear_panel(stage)]

        current_scene == :ending ->
          [build_ending_panel()]

        current_scene == content.game_over_scene() ->
          [build_game_over_panel(stage, retries_left)]

        true ->
          [build_playing_hud(stage, retries_left)]
      end

    {:canvas, nodes}
  end

  defp build_title_panel do
    children = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Rolling Ball", {0.3, 0.8, 1.0, 1.0}, 36.0, true}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Roll the ball to the goal!", {0.71, 0.78, 0.86, 1.0}, 16.0, false}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "WASD / Arrow Keys: Move", {0.59, 0.67, 0.75, 1.0}, 13.0, false}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Reach the green goal to clear the stage", {0.59, 0.67, 0.75, 1.0}, 13.0, false},
       []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:button, "  START GAME  ", "__start__", {0.16, 0.39, 0.78, 1.0}, 200.0, 50.0}, []}
    ]

    {:node, {:center, {0.0, 0.0}, :wrap},
     {:rect, {0.02, 0.02, 0.08, 0.9}, 16.0, {{0.39, 0.63, 1.0, 1.0}, 2.0}},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 8.0, {60.0, 40.0, 60.0, 40.0}},
        children}
     ]}
  end

  defp build_stage_clear_panel(stage) do
    children = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "STAGE CLEAR!", {0.39, 1.0, 0.47, 1.0}, 40.0, true}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Stage #{stage} Complete", {0.78, 0.86, 0.78, 1.0}, 18.0, false}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:button, "  NEXT STAGE  ", "__next_stage__", {0.12, 0.55, 0.24, 1.0}, 200.0, 50.0}, []}
    ]

    {:node, {:center, {0.0, 0.0}, :wrap},
     {:rect, {0.02, 0.12, 0.04, 0.9}, 16.0, {{0.31, 0.86, 0.39, 1.0}, 2.0}},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 12.0, {60.0, 40.0, 60.0, 40.0}},
        children}
     ]}
  end

  defp build_ending_panel do
    children = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "CONGRATULATIONS!", {1.0, 0.86, 0.31, 1.0}, 40.0, true}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "All stages cleared!", {0.86, 0.78, 0.59, 1.0}, 18.0, false}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:button, "  BACK TO TITLE  ", "__back_to_title__", {0.47, 0.31, 0.08, 1.0}, 200.0, 50.0},
       []}
    ]

    {:node, {:center, {0.0, 0.0}, :wrap},
     {:rect, {0.08, 0.04, 0.16, 0.92}, 16.0, {{0.86, 0.71, 0.31, 1.0}, 2.0}},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 12.0, {60.0, 40.0, 60.0, 40.0}},
        children}
     ]}
  end

  defp build_game_over_panel(_stage, _retries_left) do
    children = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "GAME OVER", {1.0, 0.31, 0.31, 1.0}, 40.0, true}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:button, "  RETRY  ", "__retry__", {0.63, 0.16, 0.16, 1.0}, 160.0, 44.0}, []}
    ]

    {:node, {:center, {0.0, 0.0}, :wrap},
     {:rect, {0.08, 0.02, 0.02, 0.92}, 16.0, {{0.78, 0.24, 0.24, 1.0}, 2.0}},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 16.0, {50.0, 35.0, 50.0, 35.0}},
        children}
     ]}
  end

  defp build_playing_hud(stage, retries_left) do
    children = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Stage #{stage}", {1.0, 0.86, 0.31, 1.0}, 14.0, true}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "Lives: #{retries_left}", {1.0, 0.59, 0.59, 1.0}, 14.0, false}, []}
    ]

    {:node, {:top_left, {8.0, 8.0}, :wrap}, {:rect, {0.0, 0.0, 0.0, 0.71}, 6.0, :none},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:horizontal_layout, 8.0, {12.0, 8.0, 12.0, 8.0}},
        children}
     ]}
  end
end
