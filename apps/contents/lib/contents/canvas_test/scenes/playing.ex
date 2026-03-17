defmodule Content.CanvasTest.Scenes.Playing do
  @moduledoc """
  CanvasTest のプレイ中シーン。

  1人称（FPS）カメラで自由移動できるデバッグ空間。
  カメラ姿勢（位置・Yaw・Pitch）・HUD表示フラグを Elixir 側で管理する。
  物理エンジンは使用しない。

  Phase 2 移行: ワールド空間の Canvas パネルを Object 階層で表現する。
  各パネルは Contents.Objects.Core.Struct で、transform に 3D 位置を保持する。
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

  @tick_sec 1.0 / 60.0

  @move_speed 5.0
  @sprint_speed 10.0
  @mouse_sensitivity 0.002
  @pitch_clamp 1.396

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    origin = Transform.new()
    world_panels = build_world_panel_objects()

    {:ok,
     %{
       origin: origin,
       children: world_panels,
       pos: {0.0, 1.7, 0.0},
       yaw: 0.0,
       pitch: 0.0,
       move_input: {0.0, 0.0},
       mouse_delta: {0.0, 0.0},
       sprint: false,
       hud_visible: false,
       # カーソルグラブ要求: :grab | :release | :no_change
       # RenderComponent が毎フレーム読み取り、Rust へ送信後 :no_change にリセットする
       cursor_grab_request: :no_change
     }}
  end

  # ワールド空間に配置するテキストパネルを Object として作成する。
  # 各 Object の transform.position に 3D 座標を保持。描画は RenderComponent が既存ロジックで行う。
  defp build_world_panel_objects do
    panel_y = 1.5

    panel_definitions = [
      %{name: "WorldPanel_Hello", position: {5.0, panel_y, -5.0}},
      %{name: "WorldPanel_Debug", position: {-5.0, panel_y, -5.0}},
      %{name: "WorldPanel_Title", position: {0.0, panel_y, -10.0}},
      %{name: "WorldPanel_Info", position: {8.0, panel_y, 0.0}}
    ]

    for panel_def <- panel_definitions do
      ObjectStruct.new(
        name: panel_def.name,
        transform: %Transform{position: panel_def.position}
      )
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
end
