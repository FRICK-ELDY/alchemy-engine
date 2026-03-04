defmodule GameContent.RollingBall.Scenes.Playing do
  @moduledoc """
  RollingBall のプレイ中シーン。

  Elixir 側で3D物理を近似する：
  - WASD 入力 → XZ 方向の加速度
  - 慣性（速度が徐々に減衰）
  - フロア端でのクランプ（フロア外に出ない）
  - 穴への落下判定（Y 座標が一定以下 → GameOver）
  - 障害物との衝突（弾き返し）
  - 動く障害物の往復移動
  - ゴールへの到達判定 → StageClear

  ## state 構造
  ```
  %{
    stage: 1..3,
    retries_left: 0..3,
    ball: {x, y, z},           # ボールのワールド座標
    vx: float,                  # X 方向速度
    vz: float,                  # Z 方向速度
    vy: float,                  # Y 方向速度（落下中のみ使用）
    falling: boolean,           # 穴に落ちているか
    cleared: boolean,           # ゴールに到達したか
    floor_tiles: [{x, z}],      # フロアタイル座標リスト（描画用）
    goal_pos: {x, z},           # ゴール座標
    obstacles: [{x, z}],        # 静的障害物座標リスト
    moving_obstacles: [map],    # 動く障害物リスト
    hole_positions: [{x, z}],   # 穴のワールド座標リスト
    move_input: {dx, dz}        # 最新の移動入力
  }
  ```
  """
  @behaviour Core.SceneBehaviour

  alias GameContent.RollingBall.StageData

  @tick_sec 1.0 / 60.0

  # ボール加速度（入力あたり）
  @accel 12.0

  # 摩擦係数（速度減衰率 / フレーム）
  @friction 0.88

  # 最大速度
  @max_speed 6.0

  # 重力加速度（落下中）
  @gravity 20.0

  # 穴判定：タイルサイズが 2.0 になったため閾値を拡大（0.7 = ボール半径 0.55 + 余裕）
  @hole_threshold 0.7

  # 落下完了 Y 座標（これ以下になったら GameOver）
  @fall_depth -6.0

  # ゴール判定半径（ゴール half_xz=0.7 + ボール half=0.55）
  @goal_radius 1.1

  # 障害物衝突半径（ボール半径 0.55 + 障害物半径 0.65）
  @obstacle_collision_radius 1.2

  @impl Core.SceneBehaviour
  def init(%{stage: stage, retries_left: retries_left}) do
    stage_data = StageData.get(stage)
    {bx, bz} = stage_data.ball_start

    # フロア上面（tile_half_y * 2 = 0.16）+ ボール半径（0.55）
    ball_y = 0.16 + 0.55

    state = %{
      stage: stage,
      retries_left: retries_left,
      ball: {bx, ball_y, bz},
      vx: 0.0,
      vz: 0.0,
      vy: 0.0,
      falling: false,
      cleared: false,
      floor_tiles: StageData.floor_tiles(stage_data),
      goal_pos: stage_data.goal_pos,
      obstacles: stage_data.obstacles,
      moving_obstacles: stage_data.moving_obstacles,
      hole_positions: StageData.hole_positions(stage_data),
      move_input: {0.0, 0.0}
    }

    {:ok, state}
  end

  @impl Core.SceneBehaviour
  def render_type, do: :playing

  @impl Core.SceneBehaviour
  def update(_context, state) do
    cond do
      state.cleared ->
        next_stage = state.stage + 1

        if next_stage > StageData.max_stage() do
          {:transition, {:replace, GameContent.RollingBall.Scenes.Ending, %{}}, state}
        else
          {:transition,
           {:replace, GameContent.RollingBall.Scenes.StageClear,
            %{next_stage: next_stage, retries_left: state.retries_left}}, state}
        end

      state.falling and ball_y(state) <= @fall_depth ->
        {:transition,
         {:replace, GameContent.RollingBall.Scenes.GameOver,
          %{stage: state.stage, retries_left: state.retries_left - 1}}, state}

      true ->
        {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
        new_state = tick(state, dx, dz)
        {:continue, new_state}
    end
  end

  # ── 物理ティック ──────────────────────────────────────────────────

  defp tick(state, dx, dz) do
    state
    |> apply_input(dx, dz)
    |> update_moving_obstacles()
    |> update_ball_position()
    |> check_hole()
    |> check_goal()
  end

  defp apply_input(state, dx, dz) do
    if state.falling do
      state
    else
      len = :math.sqrt(dx * dx + dz * dz)

      {ax, az} =
        if len > 0.001 do
          {dx / len * @accel * @tick_sec, dz / len * @accel * @tick_sec}
        else
          {0.0, 0.0}
        end

      new_vx = clamp((state.vx + ax) * @friction, -@max_speed, @max_speed)
      new_vz = clamp((state.vz + az) * @friction, -@max_speed, @max_speed)

      %{state | vx: new_vx, vz: new_vz}
    end
  end

  defp update_moving_obstacles(state) do
    stage_data = StageData.get(state.stage)
    half = stage_data.floor_size / 2.0 * stage_data.tile_size

    new_moving =
      Enum.map(state.moving_obstacles, fn obs ->
        nx = obs.x + obs.vx * @tick_sec
        nz = obs.z + obs.vz * @tick_sec

        # 往復範囲（初期位置からの距離）または フロア端を超えたら速度反転
        {nx2, new_vx} =
          if abs(nx) > obs.range or nx < -half + 1.0 or nx > half - 1.0 do
            {obs.x, -obs.vx}
          else
            {nx, obs.vx}
          end

        {nz2, new_vz} =
          if abs(nz) > obs.range or nz < -half + 1.0 or nz > half - 1.0 do
            {obs.z, -obs.vz}
          else
            {nz, obs.vz}
          end

        %{obs | x: nx2, z: nz2, vx: new_vx, vz: new_vz}
      end)

    %{state | moving_obstacles: new_moving}
  end

  defp update_ball_position(state) do
    {bx, by, bz} = state.ball

    if state.falling do
      new_vy = state.vy - @gravity * @tick_sec
      new_by = by + new_vy * @tick_sec
      %{state | ball: {bx, new_by, bz}, vy: new_vy}
    else
      stage_data = StageData.get(state.stage)
      # フロア端 = グリッド数 / 2 * タイルサイズ - ボール半径分の余白
      half = stage_data.floor_size / 2.0 * stage_data.tile_size - 0.6

      new_bx = clamp(bx + state.vx * @tick_sec, -half, half)
      new_bz = clamp(bz + state.vz * @tick_sec, -half, half)

      # 壁クランプで速度をゼロにする
      new_vx = if new_bx != bx + state.vx * @tick_sec, do: 0.0, else: state.vx
      new_vz = if new_bz != bz + state.vz * @tick_sec, do: 0.0, else: state.vz

      {nx, nz, nvx, nvz} =
        resolve_obstacle_collisions(new_bx, new_bz, new_vx, new_vz, state)

      %{state | ball: {nx, by, nz}, vx: nvx, vz: nvz}
    end
  end

  defp resolve_obstacle_collisions(bx, bz, vx, vz, state) do
    all_obstacles =
      state.obstacles ++
        Enum.map(state.moving_obstacles, fn %{x: x, z: z} -> {x, z} end)

    Enum.reduce(all_obstacles, {bx, bz, vx, vz}, fn {ox, oz}, {cx, cz, cvx, cvz} ->
      ddx = cx - ox
      ddz = cz - oz
      dist = :math.sqrt(ddx * ddx + ddz * ddz)

      if dist < @obstacle_collision_radius and dist > 0.001 do
        # 押し出し
        nx_x = ddx / dist
        nx_z = ddz / dist
        overlap = @obstacle_collision_radius - dist
        new_cx = cx + nx_x * overlap
        new_cz = cz + nx_z * overlap

        # 速度を法線方向に反射（反発係数 0.5）
        dot = cvx * nx_x + cvz * nx_z
        new_vx = cvx - 2.0 * dot * nx_x * 0.5
        new_vz = cvz - 2.0 * dot * nx_z * 0.5

        {new_cx, new_cz, new_vx, new_vz}
      else
        {cx, cz, cvx, cvz}
      end
    end)
  end

  defp check_hole(state) do
    if state.falling do
      state
    else
      {bx, _by, bz} = state.ball

      falling =
        Enum.any?(state.hole_positions, fn {hx, hz} ->
          dx = bx - hx
          dz = bz - hz
          dx * dx + dz * dz < @hole_threshold * @hole_threshold
        end)

      if falling do
        %{state | falling: true, vy: 0.0}
      else
        state
      end
    end
  end

  defp check_goal(state) do
    if state.falling or state.cleared do
      state
    else
      {bx, _by, bz} = state.ball
      {gx, gz} = state.goal_pos
      dx = bx - gx
      dz = bz - gz
      dist_sq = dx * dx + dz * dz

      if dist_sq < @goal_radius * @goal_radius do
        %{state | cleared: true}
      else
        state
      end
    end
  end

  # ── ヘルパー ─────────────────────────────────────────────────────

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp ball_y(%{ball: {_x, y, _z}}), do: y
end
