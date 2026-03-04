defmodule Content.VRTest.Scenes.Playing do
  @moduledoc """
  VRTest のプレイ中シーン。

  Phase A: マウスドラッグでカメラ回転し、3D空間を見渡す。
  - カメラはプレイヤー位置（原点）で固定、yaw/pitch で向きを制御
  - 敵に触れるとゲームオーバー（SimpleBox3D と同様）
  """
  @behaviour Core.SceneBehaviour

  @tick_sec 1.0 / 60.0

  # フィールドサイズ
  @field_half 10.0

  # プレイヤー移動速度（WASD、Phase A では未使用でも InputComponent 互換のため）
  @player_speed 5.0

  # 敵の移動速度
  @enemy_speed 2.5

  # 衝突判定半径
  @player_radius 0.5
  @enemy_radius 0.5

  # 敵の初期位置
  @initial_enemies [
    {8.0, 0.0, 8.0},
    {-8.0, 0.0, 8.0},
    {8.0, 0.0, -8.0},
    {-8.0, 0.0, -8.0}
  ]

  @impl Core.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       player: {0.0, 0.0, 0.0},
       enemies: @initial_enemies,
       alive: true,
       camera_yaw: 0.0,
       camera_pitch: 0.0,
       move_input: {0.0, 0.0},
       cursor_grabbed: false,
       cursor_grab_request: :grab
     }}
  end

  @impl Core.SceneBehaviour
  def render_type, do: :playing

  @impl Core.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :alive, true) do
      {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
      new_state = tick(state, dx, dz)
      {:continue, new_state}
    else
      {:transition, {:replace, Content.VRTest.Scenes.GameOver, %{}}, state}
    end
  end

  # ── ゲームロジック ────────────────────────────────────────────────

  defp tick(state, dx, dz) do
    {px, py, pz} = state.player
    new_player = move_player(px, py, pz, dx, dz)
    new_enemies = move_enemies(state.enemies, new_player)
    alive = not collides_any?(new_player, new_enemies)

    %{state | player: new_player, enemies: new_enemies, alive: alive}
  end

  defp move_player(px, _py, pz, dx, dz) do
    speed = @player_speed * @tick_sec
    len = :math.sqrt(dx * dx + dz * dz)

    {nx, nz} =
      if len > 0.001 do
        {dx / len * speed + px, dz / len * speed + pz}
      else
        {px, pz}
      end

    clamped_x = max(-@field_half, min(@field_half, nx))
    clamped_z = max(-@field_half, min(@field_half, nz))
    {clamped_x, 0.0, clamped_z}
  end

  defp move_enemies(enemies, {px, _py, pz}) do
    speed = @enemy_speed * @tick_sec

    Enum.map(enemies, fn {ex, ey, ez} ->
      ddx = px - ex
      ddz = pz - ez
      len = :math.sqrt(ddx * ddx + ddz * ddz)

      if len > 0.001 do
        {ex + ddx / len * speed, ey, ez + ddz / len * speed}
      else
        {ex, ey, ez}
      end
    end)
  end

  defp collides_any?({px, _py, pz}, enemies) do
    threshold = @player_radius + @enemy_radius

    Enum.any?(enemies, fn {ex, _ey, ez} ->
      dx = px - ex
      dz = pz - ez
      dx * dx + dz * dz < threshold * threshold
    end)
  end
end
