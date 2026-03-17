defmodule Contents.Components.Category.Rendering.Render do
  @moduledoc """
  どのメッシュをどのシェーダーで描画するかを組み立て、クライアントへ投げる器。

  メッシュ・シェーダーは procedural/meshes と shader を参照するだけ。
  具体的な値（カメラ・色・グリッド・HUD レイアウト等）は利用コンテンツの Playing から取得する。
  利用コンテンツが render_defaults/0 を提供する想定（現状は Content.CanvasTest.Playing のみ対応）。
  """
  @behaviour Core.Component

  alias Contents.Components.Category.Shader.Skybox
  alias Contents.Components.Category.Procedural.Meshes.Box

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

    defaults = Content.CanvasTest.Playing.render_defaults()

    commands = build_commands(defaults)
    camera = build_camera(playing_state, defaults)
    ui = build_ui(playing_state, context, defaults)
    cursor_grab = Map.get(playing_state, :cursor_grab_request, :no_change)

    frame_binary = Content.MessagePackEncoder.encode_frame(commands, camera, ui, [])
    Contents.FrameBroadcaster.put(context.room_id, frame_binary)

    if cursor_grab != :no_change and runner do
      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &apply_cursor_grab_request(&1, cursor_grab)
      )
    end

    :ok
  end

  defp apply_cursor_grab_request(state, cursor_grab) do
    if state.cursor_grab_request == cursor_grab do
      Map.put(state, :cursor_grab_request, :no_change)
    else
      state
    end
  end

  defp build_commands(defaults) do
    grid_vertices =
      Content.MeshDef.grid_plane(
        size: defaults.grid_size,
        divisions: defaults.grid_divisions,
        color: defaults.color_grid
      )[:vertices]

    half = 0.5
    w = defaults.color_box_white
    g = defaults.color_box_gray

    [
      Skybox.skybox_command(defaults.color_sky_top, defaults.color_sky_bottom),
      {:grid_plane_verts, grid_vertices},
      Box.box_3d_command(5.0, half, -5.0, half, half, half, w),
      Box.box_3d_command(-5.0, half, -5.0, half, half, half, g),
      Box.box_3d_command(0.0, half, -10.0, half, half, half, w),
      Box.box_3d_command(8.0, half, 0.0, half, half, half, g)
    ]
  end

  defp build_camera(state, defaults) do
    {px, py, pz} = Map.get(state, :pos, {0.0, 1.7, 0.0})
    yaw = Map.get(state, :yaw, 0.0)
    pitch = Map.get(state, :pitch, 0.0)
    {fx, fy, fz} = forward_vec(yaw, pitch)
    target = {px + fx, py + fy, pz + fz}
    {fov, near, far} = defaults.camera
    {:camera_3d, {px, py, pz}, target, {0.0, 1.0, 0.0}, {fov, near, far}}
  end

  defp forward_vec(yaw, pitch) do
    fx = :math.cos(pitch) * :math.sin(yaw)
    fy = :math.sin(pitch)
    fz = :math.cos(pitch) * -:math.cos(yaw)
    {fx, fy, fz}
  end

  defp build_ui(state, context, defaults) do
    hud_visible = Map.get(state, :hud_visible, false)
    world_nodes = build_world_nodes_from_objects(state, context, defaults)
    hud_nodes = if hud_visible, do: hud_layout_nodes(), else: []
    {:canvas, world_nodes ++ hud_nodes}
  end

  defp hud_layout_nodes do
    [
      {:node, {:center, {0.0, 0.0}, :wrap},
       {:rect, {0.05, 0.05, 0.08, 0.88}, 12.0, {{0.4, 0.4, 0.5, 0.9}, 1.5}},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:vertical_layout, 10.0, {40.0, 30.0, 40.0, 30.0}},
          hud_panel_contents()}
       ]}
    ]
  end

  defp hud_panel_contents do
    [
      hud_title(),
      hud_separator(),
      hud_text("WASD  : Move"),
      hud_text("Mouse : Look"),
      hud_text("Shift : Sprint"),
      hud_text("ESC   : Close this menu"),
      hud_separator(),
      hud_quit_button()
    ]
  end

  defp hud_title do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:text, "DEBUG MENU", {0.9, 0.95, 1.0, 1.0}, 28.0, true}, []}
  end

  defp hud_separator do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
  end

  defp hud_text(text) do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:text, text, {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []}
  end

  defp hud_quit_button do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 140.0, 40.0}, []}
  end

  defp build_world_nodes_from_objects(state, context, defaults) do
    children = Map.get(state, :children, [])
    {px, py, pz} = Map.get(state, :pos, {0.0, 1.7, 0.0})
    pos_text = "Pos: (#{Float.round(px, 1)}, #{Float.round(py, 1)}, #{Float.round(pz, 1)})"
    fps_text = if context.tick_ms > 0, do: "FPS: #{round(1000.0 / context.tick_ms)}", else: "FPS: --"
    info_text = "[INFO]\n#{fps_text}\n#{pos_text}"
    static_texts = defaults.world_panel_static_texts
    texts = static_texts ++ [info_text]
    lifetime = defaults.world_text_lifetime
    color = defaults.world_text_color

    for {obj, text} <- Enum.zip(Enum.take(children, length(texts)), texts), obj.active do
      {x, y, z} = obj.transform.position
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, x, y, z, text, color, {lifetime, lifetime}}, []}
    end
  end
end
