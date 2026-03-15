defmodule Content.CanvasTest.RenderComponent do
  @moduledoc """
  毎フレーム DrawCommand リスト・Camera3D・UiCanvas を組み立てて
  FrameBroadcaster.put で Zenoh へ配信するコンポーネント。

  ## 描画内容
  - `DrawCommand::Skybox`    — 空色グラデーション背景
  - `DrawCommand::GridPlane` — XZ 平面グリッド地面（40×40）
  - `DrawCommand::Box3D`     — ワールド内の目印ボックス
  - HUD Canvas               — ESC キーで表示/非表示（DEBUG MENU）
  - World Canvas             — 3D 空間内固定テキストパネル（毎フレーム再送）
  """
  @behaviour Core.Component

  # カメラ設定
  @camera_fov 75.0
  @camera_near 0.1
  @camera_far 200.0

  # 色定義
  @color_sky_top {0.35, 0.55, 0.85, 1.0}
  @color_sky_bottom {0.65, 0.80, 1.0, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_box_white {1.0, 1.0, 1.0, 1.0}
  @color_box_gray {0.5, 0.5, 0.5, 1.0}

  # グリッドパラメータ
  @grid_size 40.0
  @grid_divisions 40

  # ワールドテキストの常時表示用 lifetime（f64 として送る必要があるため float）
  @world_text_lifetime 9999.0
  @world_text_color {0.9, 0.95, 1.0, 1.0}

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    commands = build_commands()
    camera = build_camera(playing_state)
    ui = build_ui(playing_state, context)
    cursor_grab = Map.get(playing_state, :cursor_grab_request, :no_change)

    frame_binary = Content.MessagePackEncoder.encode_frame(commands, camera, ui, [])
    Contents.FrameBroadcaster.put(context.room_id, frame_binary)

    # 送信した要求と現在値が一致する場合のみリセットする。
    # on_nif_sync と on_event は別プロセスから並行して呼ばれる可能性があるため、
    # 読み取り後に「異なる値」の要求が書き込まれた場合は上書きしない。
    #
    # 残存する制約: 読み取り後に「同じ値」の要求が再書き込みされた場合
    # （例: Escape 連打で :release が2回書き込まれた場合）は区別できず上書きされる。
    # この場合でも次の Escape 押下で再送されるため、実害は1フレームの遅延に留まる。
    # 完全なアトミック性が必要な場合はシーケンス番号の導入を検討すること。
    if cursor_grab != :no_change and runner do
      Contents.SceneStack.update_by_scene_type(
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

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands do
    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {wr, wg, wb, wa} = @color_box_white
    {gr, gg, gb, ga} = @color_box_gray

    half = 0.5

    grid_vertices =
      Content.MeshDef.grid_plane(
        size: @grid_size,
        divisions: @grid_divisions,
        color: {grid_r, grid_g, grid_b, grid_a}
      )[:vertices]

    [
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}},
      {:grid_plane_verts, grid_vertices},
      {:box_3d, 5.0, half, -5.0, half, half, {half, wr, wg, wb, wa}},
      {:box_3d, -5.0, half, -5.0, half, half, {half, gr, gg, gb, ga}},
      {:box_3d, 0.0, half, -10.0, half, half, {half, wr, wg, wb, wa}},
      {:box_3d, 8.0, half, 0.0, half, half, {half, gr, gg, gb, ga}}
    ]
  end

  # ── カメラ組み立て（1人称 FPS）─────────────────────────────────────

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

  # ── UiCanvas 組み立て ─────────────────────────────────────────────

  defp build_ui(state, context) do
    hud_visible = Map.get(state, :hud_visible, false)
    {px, py, pz} = Map.get(state, :pos, {0.0, 1.7, 0.0})

    pos_text =
      "Pos: (#{Float.round(px, 1)}, #{Float.round(py, 1)}, #{Float.round(pz, 1)})"

    fps_text =
      if context.tick_ms > 0,
        do: "FPS: #{round(1000.0 / context.tick_ms)}",
        else: "FPS: --"

    world_nodes = [
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, 5.0, 1.5, -5.0, "Hello, World Canvas!", @world_text_color,
        {@world_text_lifetime, @world_text_lifetime}}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, -5.0, 1.5, -5.0, "CanvasUI Debug Panel\nThis is a world-space canvas.",
        @world_text_color, {@world_text_lifetime, @world_text_lifetime}}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, 0.0, 1.5, -10.0, "Alchemy Engine\nCanvas Test v0.1", @world_text_color,
        {@world_text_lifetime, @world_text_lifetime}}, []},
      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, 8.0, 1.5, 0.0, "[INFO]\n#{fps_text}\n#{pos_text}", @world_text_color,
        {@world_text_lifetime, @world_text_lifetime}}, []}
    ]

    hud_nodes =
      if hud_visible do
        [
          {:node, {:center, {0.0, 0.0}, :wrap},
           {:rect, {0.05, 0.05, 0.08, 0.88}, 12.0, {{0.4, 0.4, 0.5, 0.9}, 1.5}},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 10.0, {40.0, 30.0, 40.0, 30.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "DEBUG MENU", {0.9, 0.95, 1.0, 1.0}, 28.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "WASD  : Move", {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "Mouse : Look", {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "Shift : Sprint", {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "ESC   : Close this menu", {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 140.0, 40.0}, []}
              ]}
           ]}
        ]
      else
        []
      end

    {:canvas, world_nodes ++ hud_nodes}
  end
end
