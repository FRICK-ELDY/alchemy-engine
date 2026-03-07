defmodule Content.Telemetry.RenderComponent do
  @moduledoc """
  Telemetry の描画コンポーネント。

  MenuComponent の表示状態に応じてメニュー UI を表示し、
  メニュー表示中はマウスロックを解除する。
  """
  @behaviour Core.Component

  @camera_fov 75.0
  @camera_near 0.1
  @camera_far 200.0

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)
    room_id = Map.get(context, :room_id, :main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    commands = build_commands()
    camera = build_camera(playing_state)

    menu_visible = Contents.MenuComponent.get_menu_visible(room_id)

    menu_nodes =
      if menu_visible, do: Contents.MenuComponent.get_menu_ui(room_id, context), else: []

    ui = {:canvas, menu_nodes}

    # メニュー表示中は毎フレーム :release を送り、クリックでグラブされるのを防ぐ
    cursor_grab = if menu_visible, do: :release, else: :grab

    frame_binary = Content.MessagePackEncoder.encode_frame(commands, camera, ui, [])
    Core.NifBridge.push_render_frame_binary(context.render_buf_ref, frame_binary, cursor_grab)

    :ok
  end

  defp build_commands do
    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = {0.15, 0.25, 0.4, 1.0}
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = {0.4, 0.55, 0.75, 1.0}
    {grid_r, grid_g, grid_b, grid_a} = {0.2, 0.22, 0.28, 1.0}

    grid_vertices =
      Content.MeshDef.grid_plane(
        size: 20.0,
        divisions: 20,
        color: {grid_r, grid_g, grid_b, grid_a}
      )[:vertices]

    [
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}},
      {:grid_plane_verts, grid_vertices}
    ]
  end

  defp build_camera(state) do
    {px, py, pz} = Map.get(state, :pos, {0.0, 1.7, 0.0})
    yaw = Map.get(state, :yaw, 0.0)
    pitch = Map.get(state, :pitch, 0.0)

    {fx, fy, fz} = forward_vec(yaw, pitch)
    target = {px + fx, py + fy, pz + fz}

    {:camera_3d, {px, py, pz}, target, {0.0, 1.0, 0.0}, {@camera_fov, @camera_near, @camera_far}}
  end

  defp forward_vec(yaw, pitch) do
    fx = :math.cos(pitch) * :math.sin(yaw)
    fy = :math.sin(pitch)
    fz = :math.cos(pitch) * -:math.cos(yaw)
    {fx, fy, fz}
  end
end
