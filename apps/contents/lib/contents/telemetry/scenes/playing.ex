defmodule Content.Telemetry.Scenes.Playing do
  @moduledoc """
  Telemetry のプレイ中シーン。

  1人称（FPS）カメラで WASD 移動・Shift ダッシュ・マウス見渡しをサポートする。
  メニュー表示は MenuComponent が管理し、入力状態は LocalUserComponent が保持する。
  """
  @behaviour Contents.SceneBehaviour

  @tick_sec 1.0 / 60.0
  @move_speed 5.0
  @sprint_speed 10.0
  @mouse_sensitivity 0.004
  @pitch_clamp 1.396

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       pos: {0.0, 1.7, 0.0},
       yaw: 0.0,
       pitch: 0.0,
       move_input: {0.0, 0.0},
       mouse_delta: {0.0, 0.0},
       sprint: false
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    new_state = tick(state)
    {:continue, new_state}
  end

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
      ndx = dx / len
      ndz = dz / len

      sin_yaw = :math.sin(yaw)
      cos_yaw = :math.cos(yaw)

      world_x = ndx * cos_yaw - ndz * sin_yaw
      world_z = ndx * sin_yaw + ndz * cos_yaw

      {px + world_x * step, py, pz + world_z * step}
    else
      {px, py, pz}
    end
  end
end
