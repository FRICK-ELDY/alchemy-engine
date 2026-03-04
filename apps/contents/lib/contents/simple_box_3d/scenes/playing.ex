defmodule Content.SimpleBox3D.Scenes.Playing do
  @moduledoc """
  SimpleBox3D のプレイ中シーン。

  Elixir 側で3D座標を管理し、毎フレーム RenderComponent に描画を委譲する。
  Rust 物理エンジンは使用せず、シンプルな座標更新ロジックを Elixir 側で実装する。

  ## ゲームルール
  - プレイヤー（青ボックス）は WASD で移動する
  - 敵（赤ボックス）はプレイヤーを追跡する
  - 敵に触れるとゲームオーバー
  """
  @behaviour Contents.SceneBehaviour

  @tick_sec 1.0 / 60.0

  # フィールドサイズ（グリッドに合わせる）
  @field_half 10.0

  # プレイヤー移動速度（単位/秒）
  @player_speed 5.0

  # 敵の移動速度（単位/秒）
  @enemy_speed 2.5

  # 衝突判定半径
  @player_radius 0.5
  @enemy_radius 0.5

  # 敵の初期位置リスト（プレイヤーから離れた位置）
  @initial_enemies [
    {8.0, 0.0, 8.0},
    {-8.0, 0.0, 8.0},
    {8.0, 0.0, -8.0},
    {-8.0, 0.0, -8.0}
  ]

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       player: {0.0, 0.0, 0.0},
       enemies: @initial_enemies,
       alive: true
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :alive, true) do
      # move_input は Rust の on_move_input が f64 としてエンコードするため float で届く。
      {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
      new_state = tick(state, dx, dz)
      {:continue, new_state}
    else
      {:transition, {:replace, Content.SimpleBox3D.Scenes.GameOver, %{}}, state}
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
