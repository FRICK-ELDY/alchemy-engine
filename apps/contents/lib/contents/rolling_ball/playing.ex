defmodule Content.RollingBall.Playing do
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

  Phase 6 移行: ボールを Contents.Objects.Core.Struct で表現。
  transform.position で座標を保持。物理計算は Object の transform を更新する形に変更。
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

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

  # 描画用定数
  @tile_size 2.0
  @tile_half_xz 0.98
  @tile_half_y 0.08
  @ball_half 0.55
  @goal_half_xz 0.7
  @goal_half_y 1.0
  @obstacle_half 0.65
  @camera_eye {0.0, 28.0, 22.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 150.0
  @color_sky_top {0.55, 0.15, 0.10, 1.0}
  @color_sky_bottom {1.0, 0.55, 0.15, 1.0}
  @color_floor {0.55, 0.55, 0.60, 1.0}
  @color_ball {1.0, 1.0, 1.0, 1.0}
  @color_goal {0.1, 0.95, 0.3, 1.0}
  @color_obstacle {0.95, 0.15, 0.15, 1.0}
  @color_moving_obstacle {1.0, 0.55, 0.05, 1.0}

  @max_stage 3

  @impl Contents.SceneBehaviour
  def init(%{stage: stage, retries_left: retries_left}) do
    stage_data = get_stage_data(stage)
    {bx, bz} = stage_data.ball_start

    # フロア上面（tile_half_y * 2 = 0.16）+ ボール半径（0.55）
    ball_y = 0.16 + 0.55

    ball_object =
      ObjectStruct.new(
        name: "Ball",
        transform: %Transform{position: {bx, ball_y, bz}}
      )

    state = %{
      stage: stage,
      retries_left: retries_left,
      ball_object: ball_object,
      vx: 0.0,
      vz: 0.0,
      vy: 0.0,
      falling: false,
      cleared: false,
      floor_tiles: floor_tiles(stage_data),
      goal_pos: stage_data.goal_pos,
      obstacles: stage_data.obstacles,
      moving_obstacles: stage_data.moving_obstacles,
      hole_positions: hole_positions(stage_data),
      move_input: {0.0, 0.0}
    }

    {:ok, state}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    cond do
      state.cleared ->
        next_stage = state.stage + 1

        if next_stage > @max_stage do
          {:transition, {:replace, Content.RollingBall.Ending, %{}}, state}
        else
          {:transition,
           {:replace, Content.RollingBall.StageClear,
            %{next_stage: next_stage, retries_left: state.retries_left}}, state}
        end

      state.falling and ball_y(state) <= @fall_depth ->
        {:transition,
         {:replace, Content.RollingBall.GameOver,
          %{stage: state.stage, retries_left: state.retries_left - 1}}, state}

      true ->
        {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
        new_state = tick(state, dx, dz)
        {:continue, new_state}
    end
  end

  @doc """
  1 フレーム分の描画データを組み立てる。Rendering.Render が Content.build_frame 経由で呼ぶ。
  """
  def build_frame(playing_state, context) do
    content = Core.Config.current()
    current_scene = Map.get(context, :current_scene, content.playing_scene())

    commands = build_frame_commands(playing_state, current_scene)
    camera = build_frame_camera()
    ui = build_frame_ui(playing_state, current_scene, content)
    {commands, camera, ui}
  end

  # ── ステージデータ（StageData を内包）─────────────────────────────────────

  defp get_stage_data(1) do
    %{
      stage: 1,
      floor_size: 8,
      tile_size: @tile_size,
      ball_start: {-6.0, -6.0},
      goal_pos: {6.0, 6.0},
      holes: [{2, 2}, {5, 2}, {2, 5}, {5, 5}],
      obstacles: [{0.0, 0.0}],
      moving_obstacles: []
    }
  end

  defp get_stage_data(2) do
    %{
      stage: 2,
      floor_size: 10,
      tile_size: @tile_size,
      ball_start: {-8.0, -8.0},
      goal_pos: {8.0, 8.0},
      holes: [{1, 1}, {4, 1}, {8, 1}, {1, 4}, {8, 4}, {1, 8}, {4, 8}, {8, 8}],
      obstacles: [{2.0, 0.0}, {-2.0, 0.0}, {0.0, 2.0}, {0.0, -2.0}],
      moving_obstacles: []
    }
  end

  defp get_stage_data(3) do
    %{
      stage: 3,
      floor_size: 10,
      tile_size: @tile_size,
      ball_start: {-8.0, -8.0},
      goal_pos: {8.0, 8.0},
      holes:
        [{1, 1}, {5, 1}, {8, 1}, {1, 5}, {8, 5}, {1, 8}, {5, 8}, {8, 8}, {3, 3}, {6, 3}, {3, 6},
         {6, 6}, {4, 0}, {0, 4}, {9, 4}, {4, 9}],
      obstacles: [{4.0, 0.0}, {-4.0, 0.0}, {0.0, 4.0}, {0.0, -4.0}],
      moving_obstacles: [
        %{id: 0, x: 2.0, z: 2.0, vx: 3.0, vz: 0.0, range: 4.0},
        %{id: 1, x: -2.0, z: -2.0, vx: 0.0, vz: 3.0, range: 4.0},
        %{id: 2, x: 2.0, z: -2.0, vx: -3.0, vz: 0.0, range: 4.0},
        %{id: 3, x: -2.0, z: 2.0, vx: 0.0, vz: -3.0, range: 4.0}
      ]
    }
  end

  defp grid_to_world(col, row, floor_size, tile_size) do
    x = (col - floor_size / 2 + 0.5) * tile_size
    z = (row - floor_size / 2 + 0.5) * tile_size
    {x, z}
  end

  defp floor_tiles(stage_data) do
    %{floor_size: n, holes: holes, tile_size: ts} = stage_data
    hole_set = MapSet.new(holes)

    for col <- 0..(n - 1), row <- 0..(n - 1), not MapSet.member?(hole_set, {col, row}) do
      grid_to_world(col, row, n, ts)
    end
  end

  defp hole_positions(stage_data) do
    %{floor_size: n, holes: holes, tile_size: ts} = stage_data
    Enum.map(holes, fn {col, row} -> grid_to_world(col, row, n, ts) end)
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
    stage_data = get_stage_data(state.stage)
    half = stage_data.floor_size / 2.0 * stage_data.tile_size

    new_moving =
      Enum.map(state.moving_obstacles, fn obs ->
        nx = obs.x + obs.vx * @tick_sec
        nz = obs.z + obs.vz * @tick_sec

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
    {bx, by, bz} = position_from_object(state.ball_object)

    if state.falling do
      new_vy = state.vy - @gravity * @tick_sec
      new_by = by + new_vy * @tick_sec
      new_ball = put_position(state.ball_object, {bx, new_by, bz})
      %{state | ball_object: new_ball, vy: new_vy}
    else
      stage_data = get_stage_data(state.stage)
      half = stage_data.floor_size / 2.0 * stage_data.tile_size - 0.6

      new_bx = clamp(bx + state.vx * @tick_sec, -half, half)
      new_bz = clamp(bz + state.vz * @tick_sec, -half, half)

      new_vx = if new_bx != bx + state.vx * @tick_sec, do: 0.0, else: state.vx
      new_vz = if new_bz != bz + state.vz * @tick_sec, do: 0.0, else: state.vz

      {nx, nz, nvx, nvz} =
        resolve_obstacle_collisions(new_bx, new_bz, new_vx, new_vz, state)

      new_ball = put_position(state.ball_object, {nx, by, nz})
      %{state | ball_object: new_ball, vx: nvx, vz: nvz}
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
        nx_x = ddx / dist
        nx_z = ddz / dist
        overlap = @obstacle_collision_radius - dist
        new_cx = cx + nx_x * overlap
        new_cz = cz + nx_z * overlap
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
      {bx, _by, bz} = position_from_object(state.ball_object)

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
      {bx, _by, bz} = position_from_object(state.ball_object)
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

  # ── 描画 ───────────────────────────────────────────────────────────

  defp build_frame_commands(scene_state, current_scene) do
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
      moving_cmds = build_moving_obstacle_cmds(scene_state)
      ball_cmd = build_ball_cmd(scene_state)

      [skybox_cmd | floor_cmds] ++ goal_cmds ++ obstacle_cmds ++ moving_cmds ++ [ball_cmd]
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
      nil -> []
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
    # init で必ず ball_object を設定するが、position_from_object(nil) で中央にフォールバック
    ball_object = Map.get(scene_state, :ball_object)
    {bx, by, bz} = position_from_object(ball_object)
    {r, g, b, a} = @color_ball
    {:box_3d, bx, by, bz, @ball_half, @ball_half, {@ball_half, r, g, b, a}}
  end

  defp position_from_object(nil), do: {0.0, @tile_half_y * 2 + @ball_half, 0.0}
  defp position_from_object(%{transform: %{position: pos}}), do: pos
  defp position_from_object(_), do: {0.0, @tile_half_y * 2 + @ball_half, 0.0}

  defp put_position(object, {x, y, z}) do
    %{object | transform: %{object.transform | position: {x, y, z}}}
  end

  defp build_frame_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  defp build_frame_ui(playing_state, current_scene, content) do
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
       {:text, "Reach the green goal to clear the stage", {0.59, 0.67, 0.75, 1.0}, 13.0, false}, []},
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
       {:button, "  BACK TO TITLE  ", "__back_to_title__", {0.47, 0.31, 0.08, 1.0}, 200.0, 50.0}, []}
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

  # ── ヘルパー ─────────────────────────────────────────────────────

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp ball_y(%{ball_object: obj}) do
    {_x, y, _z} = position_from_object(obj)
    y
  end
end
