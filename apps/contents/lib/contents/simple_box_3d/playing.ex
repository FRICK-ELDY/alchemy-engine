defmodule Content.SimpleBox3D.Scenes.Playing do
  @moduledoc """
  SimpleBox3D のプレイ中シーン。

  Elixir 側で3D座標を管理。描画は Contents.Components.Category.Rendering.Render が
  build_frame/2 経由で呼び出す。
  Rust 物理エンジンは使用せず、シンプルな座標更新ロジックを Elixir 側で実装する。

  Phase 3 移行: プレイヤー・敵を Contents.Objects.Core.Struct で表現。
  transform.position で座標を保持。衝突判定は Object の position を比較する関数で行う。

  ## ゲームルール
  - プレイヤー（青ボックス）は WASD で移動する
  - 敵（赤ボックス）はプレイヤーを追跡する
  - 敵に触れるとゲームオーバー
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

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

  # 描画用定数（build_frame/2 で使用）
  @half_size 0.5
  @camera_eye {0.0, 18.0, 14.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 100.0
  @color_player {0.2, 0.4, 0.9, 1.0}
  @color_enemy {0.9, 0.2, 0.2, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}
  @grid_size 20.0
  @grid_divisions 20

  # 敵の初期位置リスト（プレイヤーから離れた位置）
  @initial_enemy_positions [
    {8.0, 0.0, 8.0},
    {-8.0, 0.0, 8.0},
    {8.0, 0.0, -8.0},
    {-8.0, 0.0, -8.0}
  ]

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    origin = Transform.new()

    player_object =
      ObjectStruct.new(
        name: "Player",
        transform: %Transform{position: {0.0, 0.0, 0.0}}
      )

    enemy_objects =
      for {pos, i} <- Enum.with_index(@initial_enemy_positions, 1) do
        ObjectStruct.new(
          name: "Enemy_#{i}",
          transform: %Transform{position: pos}
        )
      end

    {:ok,
     %{
       origin: origin,
       landing_object: player_object,
       player_object: player_object,
       enemy_objects: enemy_objects,
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

  @doc """
  1 フレーム分の描画データを組み立てる。Rendering.Render が Content.build_frame 経由で呼ぶ。

  補足: Playing が replace で GameOver に置き換わると、スタックに :playing が残らず
  get_scene_state(:playing) は %{} を返す。その場合 player_object / enemy_objects は
  nil / [] となり、プレイヤーは原点・敵なしで描画される。Game Over 中は UI オーバーレイで
  画面を覆うため実害はなく、この挙動で想定どおりである。
  """
  def build_frame(playing_state, context) do
    content = Core.Config.current()
    current_scene = Map.get(context, :current_scene, content.playing_scene())

    commands = build_frame_commands(playing_state)
    camera = build_frame_camera()
    ui = build_frame_ui(current_scene, content)
    {commands, camera, ui}
  end

  # ── 描画組み立て ──────────────────────────────────────────────────

  defp build_frame_commands(scene_state) do
    player_object = Map.get(scene_state, :player_object)
    enemy_objects = Map.get(scene_state, :enemy_objects, [])

    player = position_from_object(player_object)
    enemy_positions = Enum.map(enemy_objects, &position_from_object/1)

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {pr, pg, pb, pa} = @color_player
    {er, eg, eb, ea} = @color_enemy

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
        size: @grid_size,
        divisions: @grid_divisions,
        color: {grid_r, grid_g, grid_b, grid_a}
      )[:vertices]

    grid_cmd = {:grid_plane_verts, grid_vertices}

    {px, py, pz} = player

    player_cmd =
      {:box_3d, px, py + @half_size, pz, @half_size, @half_size, {@half_size, pr, pg, pb, pa}}

    enemy_cmds =
      Enum.map(enemy_positions, fn {ex, ey, ez} ->
        {:box_3d, ex, ey + @half_size, ez, @half_size, @half_size, {@half_size, er, eg, eb, ea}}
      end)

    [skybox_cmd, grid_cmd, player_cmd | enemy_cmds]
  end

  defp position_from_object(nil), do: {0.0, 0.0, 0.0}
  defp position_from_object(%{transform: %{position: pos}}), do: pos
  defp position_from_object(_), do: {0.0, 0.0, 0.0}

  defp build_frame_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  defp build_frame_ui(current_scene, content) do
    nodes =
      if current_scene == content.game_over_scene() do
        [
          {:node, {:center, {0.0, 0.0}, :wrap},
           {:rect, {0.08, 0.02, 0.02, 0.92}, 16.0, {{0.78, 0.24, 0.24, 1.0}, 2.0}},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 8.0, {50.0, 35.0, 50.0, 35.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "GAME OVER", {1.0, 0.31, 0.31, 1.0}, 40.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:button, "  RETRY  ", "__retry__", {0.63, 0.16, 0.16, 1.0}, 160.0, 44.0}, []}
              ]}
           ]}
        ]
      else
        []
      end

    {:canvas, nodes}
  end

  # ── ゲームロジック ────────────────────────────────────────────────

  defp tick(state, dx, dz) do
    new_player_pos = move_player(state.player_object.transform.position, dx, dz)
    new_enemy_positions = move_enemies(extract_positions(state.enemy_objects), new_player_pos)
    alive = not collides_any?(new_player_pos, new_enemy_positions)

    new_player_object = put_position(state.player_object, new_player_pos)
    new_enemy_objects = put_positions(state.enemy_objects, new_enemy_positions)

    %{
      state
      | player_object: new_player_object,
        enemy_objects: new_enemy_objects,
        landing_object: new_player_object,
        alive: alive
    }
  end

  defp extract_positions(objects) do
    Enum.map(objects, fn obj -> obj.transform.position end)
  end

  defp put_position(object, {x, _y, z}) do
    %{object | transform: %{object.transform | position: {x, 0.0, z}}}
  end

  defp put_positions(objects, positions) do
    Enum.zip(objects, positions)
    |> Enum.map(fn {obj, pos} -> put_position(obj, pos) end)
  end

  defp move_player({px, _py, pz}, dx, dz) do
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
