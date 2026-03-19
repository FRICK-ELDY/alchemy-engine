defmodule Content.CanvasTest.Playing do
  @moduledoc """
  CanvasTest のプレイ中シーン。

  1人称（FPS）カメラで自由移動できるデバッグ空間。
  カメラ姿勢（位置・Yaw・Pitch）・HUD表示フラグを Elixir 側で管理する。
  物理エンジンは使用しない。

  Phase 2 移行: ワールド空間の Canvas パネルを Object 階層で表現する。
  各パネルは Contents.Objects.Core.Struct で、transform に 3D 位置を保持する。
  Struct → Node → Component → Object の紐づきは FormulaTest と同様に適用。
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Contents.Objects.Core.CreateEmptyChild
  alias Structs.Category.Space.Transform
  alias Contents.Components.Category.Shader.Skybox
  alias Contents.Components.Category.Procedural.Meshes.Box

  @tick_sec 1.0 / 60.0

  @move_speed 5.0
  @sprint_speed 10.0
  @mouse_sensitivity 0.002
  @pitch_clamp 1.396

  # 描画用の既定値（build_frame/2 で参照。値の定義は Playing に集約）
  @render_camera_fov 75.0
  @render_camera_near 0.1
  @render_camera_far 200.0
  @render_color_sky_top {0.35, 0.55, 0.85, 1.0}
  @render_color_sky_bottom {0.65, 0.80, 1.0, 1.0}
  @render_color_grid {0.3, 0.3, 0.3, 1.0}
  @render_color_box_white {1.0, 1.0, 1.0, 1.0}
  @render_color_box_gray {0.5, 0.5, 0.5, 1.0}
  @render_grid_size 40.0
  @render_grid_divisions 40
  @render_world_text_lifetime 9999.0
  @render_world_text_color {0.9, 0.95, 1.0, 1.0}
  @render_world_panel_static_texts [
    "Hello, World Canvas!",
    "CanvasUI Debug Panel\nThis is a world-space canvas.",
    "Alchemy Engine\nCanvas Test v0.1"
  ]

  @doc "1 フレーム分の描画データを組み立てる。Rendering.Render が Content.build_frame 経由で呼ぶ。"
  def build_frame(state, context) do
    # Object の components は state を直接更新しない。将来 state を更新する Component を追加する場合は、
    # 呼び出し位置や戻り値の扱いの再検討が必要。
    # トップレベルの Object のみ走査。world_panels 等の子 Object の Component は実行されない。
    Contents.Objects.Components.run_components_for_objects(Map.get(state, :children, []), context)

    defaults = render_defaults()
    commands = build_frame_commands(defaults)
    camera = build_frame_camera(state, defaults)
    ui = build_frame_ui(state, context, defaults)
    {commands, camera, ui}
  end

  @doc "Rendering.Render が参照する描画用既定値"
  def render_defaults do
    %{
      camera: {@render_camera_fov, @render_camera_near, @render_camera_far},
      color_sky_top: @render_color_sky_top,
      color_sky_bottom: @render_color_sky_bottom,
      color_grid: @render_color_grid,
      color_box_white: @render_color_box_white,
      color_box_gray: @render_color_box_gray,
      grid_size: @render_grid_size,
      grid_divisions: @render_grid_divisions,
      world_text_lifetime: @render_world_text_lifetime,
      world_text_color: @render_world_text_color,
      world_panel_static_texts: @render_world_panel_static_texts
    }
  end

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    origin = Transform.new()

    top_object =
      ObjectStruct.new(name: "User", components: [Contents.Objects.Components.Noop])

    world_panels = build_world_panel_objects(top_object)

    {:ok,
     %{
       origin: origin,
       landing_object: top_object,
       children: [top_object],
       pos: {0.0, 1.7, 0.0},
       yaw: 0.0,
       pitch: 0.0,
       world_panels: world_panels,
       move_input: {0.0, 0.0},
       mouse_delta: {0.0, 0.0},
       sprint: false,
       hud_visible: false,
       # カーソルグラブ要求: :grab | :release | :no_change
       # Rendering.Render が毎フレーム読み取り、Rust へ送信後 :no_change にリセットする
       cursor_grab_request: :no_change
     }}
  end

  # ワールド空間に配置するテキストパネルを Object として作成する。
  # CreateEmptyChild で User の子として作成し、transform.position に 3D 座標を保持。
  # 描画は Rendering.Render が行う。
  defp build_world_panel_objects(top_object) do
    panel_y = 1.5

    panel_definitions = [
      %{name: "WorldPanel_Hello", position: {5.0, panel_y, -5.0}},
      %{name: "WorldPanel_Debug", position: {-5.0, panel_y, -5.0}},
      %{name: "WorldPanel_Title", position: {0.0, panel_y, -10.0}},
      %{name: "WorldPanel_Info", position: {8.0, panel_y, 0.0}}
    ]

    # init/1 では起動時エラーを即失敗させたいため raise。上位で {:error, reason} を扱う構成にすることも可。
    for panel_def <- panel_definitions do
      case CreateEmptyChild.create(top_object, name: panel_def.name) do
        {:ok, child} ->
          %{child | transform: %Transform{position: panel_def.position}}

        {:error, reason} ->
          raise "CanvasTest.Playing init: CreateEmptyChild.create failed for '#{panel_def.name}': #{inspect(reason)}"
      end
    end
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    new_state = tick(state)
    {:continue, new_state}
  end

  # ── ゲームロジック ────────────────────────────────────────────────

  defp tick(state) do
    {mdx, mdy} = state.mouse_delta

    new_yaw = state.yaw + mdx * @mouse_sensitivity

    new_pitch =
      (state.pitch - mdy * @mouse_sensitivity)
      |> max(-@pitch_clamp)
      |> min(@pitch_clamp)

    new_pos = move(state.pos, state.move_input, new_yaw, state.sprint)

    %{state | yaw: new_yaw, pitch: new_pitch, pos: new_pos, mouse_delta: {0.0, 0.0}}
  end

  defp move({px, py, pz}, {dx, dz}, yaw, sprint) do
    speed = if sprint, do: @sprint_speed, else: @move_speed
    step = speed * @tick_sec

    len = :math.sqrt(dx * dx + dz * dz)

    if len > 0.001 do
      # 入力を正規化
      ndx = dx / len
      ndz = dz / len

      sin_yaw = :math.sin(yaw)
      cos_yaw = :math.cos(yaw)

      # カメラ前方ベクトル: (sin_yaw, 0, -cos_yaw)
      # カメラ右ベクトル:   (cos_yaw, 0,  sin_yaw)
      # W/S 入力: dz = -1(W=前進) / +1(S=後退)
      # A/D 入力: dx = -1(A=左)   / +1(D=右)
      world_x = ndx * cos_yaw - ndz * sin_yaw
      world_z = ndx * sin_yaw + ndz * cos_yaw

      {px + world_x * step, py, pz + world_z * step}
    else
      {px, py, pz}
    end
  end

  # ── 描画フレーム組み立て（定義は contents に集約）───────────────────────

  defp build_frame_commands(defaults) do
    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
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

  defp build_frame_camera(state, defaults) do
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

  defp build_frame_ui(state, context, defaults) do
    hud_visible = Map.get(state, :hud_visible, false)
    world_nodes = build_frame_world_nodes(state, context, defaults)
    hud_nodes = if hud_visible, do: build_frame_hud_layout_nodes(), else: []
    {:canvas, world_nodes ++ hud_nodes}
  end

  defp build_frame_hud_layout_nodes do
    [
      {:node, {:center, {0.0, 0.0}, :wrap},
       {:rect, {0.05, 0.05, 0.08, 0.88}, 12.0, {{0.4, 0.4, 0.5, 0.9}, 1.5}},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:vertical_layout, 10.0, {40.0, 30.0, 40.0, 30.0}}, build_frame_hud_panel_contents()}
       ]}
    ]
  end

  defp build_frame_hud_panel_contents do
    [
      build_frame_hud_title(),
      build_frame_hud_separator(),
      build_frame_hud_text("WASD  : Move"),
      build_frame_hud_text("Mouse : Look"),
      build_frame_hud_text("Shift : Sprint"),
      build_frame_hud_text("ESC   : Close this menu"),
      build_frame_hud_separator(),
      build_frame_hud_quit_button()
    ]
  end

  defp build_frame_hud_title do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:text, "DEBUG MENU", {0.9, 0.95, 1.0, 1.0}, 28.0, true}, []}
  end

  defp build_frame_hud_separator do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
  end

  defp build_frame_hud_text(text) do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, text, {0.8, 0.85, 0.9, 1.0}, 15.0, false}, []}
  end

  defp build_frame_hud_quit_button do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 140.0, 40.0}, []}
  end

  defp build_frame_world_nodes(state, context, defaults) do
    world_panels = Map.get(state, :world_panels, [])
    {px, py, pz} = Map.get(state, :pos, {0.0, 1.7, 0.0})
    pos_text = "Pos: (#{Float.round(px, 1)}, #{Float.round(py, 1)}, #{Float.round(pz, 1)})"

    fps_text =
      if context.tick_ms > 0, do: "FPS: #{round(1000.0 / context.tick_ms)}", else: "FPS: --"

    info_text = "[INFO]\n#{fps_text}\n#{pos_text}"
    static_texts = defaults.world_panel_static_texts
    texts = static_texts ++ [info_text]
    lifetime = defaults.world_text_lifetime
    color = defaults.world_text_color

    for {obj, text} <- Enum.zip(Enum.take(world_panels, length(texts)), texts), obj.active do
      {x, y, z} = obj.transform.position

      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:world_text, x, y, z, text, color, {lifetime, lifetime}}, []}
    end
  end
end
