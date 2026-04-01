defmodule Content.Tetris.Frame do
  @moduledoc false

  # Near top-down: look mostly along -Y; slight Z offset so view dir is not parallel to world up.
  # Same X on eye and target (no horizontal yaw).
  @camera_cx 3.0
  @camera_cz 1.2
  @camera_eye {@camera_cx, 32.0, @camera_cz + 7.5}
  @camera_target {@camera_cx, 0.08, @camera_cz}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 48.0
  @camera_near 0.1
  @camera_far 160.0

  # Main well (10 cols, visible rows): floor + rim.
  @frame_black {0.0, 0.0, 0.0, 1.0}
  @wall_thick 0.22

  @cell 1.0
  @half @cell * 0.48

  def build(context) do
    content = Core.Config.current()
    room_id = Map.get(context, :room_id, :main)
    runner = content.flow_runner(room_id)
    current = Map.get(context, :current_scene, :title)

    case current do
      :title ->
        title_frame()

      :game_over ->
        game_over_frame(runner)

      _ ->
        playing_frame(runner, context)
    end
  end

  defp title_frame do
    commands = [skybox_cmd()]
    camera = camera_3d()
    ui = {:canvas, title_ui_nodes()}
    {commands, camera, ui}
  end

  defp game_over_frame(runner) do
    go = (runner && Contents.Scenes.Stack.get_scene_state(runner, :game_over)) || %{}
    score = Map.get(go, :score, 0)
    lines = Map.get(go, :lines, 0)

    commands = [skybox_cmd()]
    camera = camera_3d()

    ui =
      {:canvas,
       [
         {:node, {:center, {0.0, 0.0}, :wrap},
          {:rect, {0.08, 0.02, 0.02, 0.92}, 16.0, {{0.15, 0.12, 0.22, 0.92}, 2.0}},
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:vertical_layout, 10.0, {48.0, 40.0, 48.0, 40.0}},
             [
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "GAME OVER", {0.95, 0.35, 0.35, 1.0}, 36.0, true}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "Score: #{score}", {0.88, 0.9, 1.0, 1.0}, 20.0, false}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "Lines: #{lines}", {0.75, 0.82, 0.95, 1.0}, 17.0, false}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:button, "  RETRY  ", "__retry__", {0.35, 0.55, 0.95, 1.0}, 168.0, 46.0}, []}
             ]}
          ]}
       ]}

    {commands, camera, ui}
  end

  defp playing_frame(runner, context) do
    ps = (runner && Contents.Scenes.Stack.get_scene_state(runner, :playing)) || %{}

    grid = Map.get(ps, :grid, %{})
    piece = Map.get(ps, :current)
    score = Map.get(ps, :score, 0)
    lines = Map.get(ps, :lines_cleared_total, 0)
    level = Map.get(ps, :level, 1)
    next_k = Map.get(ps, :next_kind, :i)
    colors = Content.Tetris.Playing.colors()

    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
        size: 36.0,
        divisions: 36,
        color: {0.22, 0.24, 0.3, 1.0}
      )[:vertices]

    block_cmds = block_commands(grid, piece, colors, ghost_alpha: 0.36)
    next_preview = next_piece_commands(next_k, colors)
    pit_frame = pit_frame_commands()

    commands =
      [skybox_cmd(), {:grid_plane_verts, grid_vertices}] ++
        pit_frame ++ block_cmds ++ next_preview

    camera = camera_3d()

    fps =
      if context[:tick_ms] && context[:tick_ms] > 0,
        do: round(1000.0 / context[:tick_ms]),
        else: 0

    ui =
      {:canvas,
       [
         {:node, {:top_left, {10.0, 10.0}, :wrap},
          {:rect, {0.0, 0.0, 0.0, 0.72}, 8.0, :none},
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:horizontal_layout, 12.0, {10.0, 8.0, 10.0, 8.0}},
             [
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "TETRIS", {0.4, 0.85, 1.0, 1.0}, 16.0, true}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "Score #{score}", {1.0, 1.0, 1.0, 1.0}, 14.0, false}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "Lines #{lines}  Lv #{level}", {0.85, 0.9, 1.0, 1.0}, 13.0, false}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "FPS #{fps}", {0.55, 0.6, 0.65, 1.0}, 12.0, false}, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "A/D or arrows: move   W or up: rotate", {0.65, 0.72, 0.8, 1.0}, 11.0, false},
                []},
               {:node, {:top_left, {0.0, 0.0}, :wrap},
                {:text, "S or down: soft drop", {0.65, 0.72, 0.8, 1.0}, 11.0, false}, []}
             ]}
          ]}
       ]}

    {commands, camera, ui}
  end

  defp title_ui_nodes do
    [
      {:node, {:center, {0.0, 0.0}, :wrap},
       {:rect, {0.1, 0.04, 0.04, 0.88}, 18.0, {{0.08, 0.1, 0.18, 0.9}, 2.5}},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:vertical_layout, 14.0, {44.0, 36.0, 44.0, 36.0}},
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "TETRIS", {0.35, 0.75, 1.0, 1.0}, 52.0, true}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "Alchemy Engine", {0.65, 0.72, 0.8, 1.0}, 16.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:button, "  START  ", "__start__", {0.25, 0.55, 0.35, 1.0}, 200.0, 52.0}, []}
          ]}
       ]}
    ]
  end

  defp skybox_cmd do
    {:skybox, {0.12, 0.14, 0.22, 1.0}, {0.28, 0.32, 0.45, 1.0}}
  end

  # Rim for visible rows r=2..21 (floor + sides + back + front). box_3d = center + half-extents.
  defp pit_frame_commands do
    cols = Content.Tetris.Playing.cols()
    rows = Content.Tetris.Playing.rows()
    t = @wall_thick
    h_block = @half
    # Cols 0..9 outer X (cell center +/- 0.5)
    x_lo = -cols / 2
    x_hi = cols / 2
    # Rows r=2 (top visible) and r=21 (bottom) outer Z
    z_top = (2 - rows / 2 + 0.5) * @cell - @cell / 2
    z_bot = (21 - rows / 2 + 0.5) * @cell + @cell / 2
    z_mid = (z_top + z_bot) / 2
    z_span = (z_bot - z_top) / 2
    x_mid = (x_lo + x_hi) / 2
    x_span = (x_hi - x_lo) / 2

    y_floor = -0.32
    y_wall_lo = y_floor + 0.02
    y_wall_hi = h_block * 2 + 0.35
    y_wall_mid = (y_wall_lo + y_wall_hi) / 2
    y_wall_half = (y_wall_hi - y_wall_lo) / 2

    {br, bg, bb, ba} = @frame_black
    box = fn cx, cy, cz, hw, hh, hd ->
      {:box_3d, cx, cy, cz, hw, hh, {hd, br, bg, bb, ba}}
    end

    [
      # Floor
      box.(x_mid, y_floor, z_mid, x_span + t, 0.12, z_span + t),
      # Left wall
      box.(x_lo - t / 2, y_wall_mid, z_mid, t / 2, y_wall_half, z_span + t / 2),
      # Right wall
      box.(x_hi + t / 2, y_wall_mid, z_mid, t / 2, y_wall_half, z_span + t / 2),
      # Back (top / spawn side)
      box.(x_mid, y_wall_mid, z_top - t / 2, x_span + t / 2, y_wall_half, t / 2),
      # Front (bottom / stack base)
      box.(x_mid, y_wall_mid, z_bot + t / 2, x_span + t / 2, y_wall_half, t / 2)
    ]
  end

  defp camera_3d do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up
    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz}, {@camera_fov, @camera_near, @camera_far}}
  end

  defp block_commands(grid, piece, colors, opts) do
    ghost_a = Keyword.get(opts, :ghost_alpha, 0.36)

    placed =
      Enum.flat_map(grid, fn {{c, r}, kind} ->
        if r >= 2 do
          [cell_box(c, r, colors[kind])]
        else
          []
        end
      end)

    ghost =
      if piece do
        land = Content.Tetris.Playing.landing_piece(grid, piece)
        curr = MapSet.new(Content.Tetris.Playing.piece_world_cells(piece))

        {cr, cg, cb, _} = colors[piece.kind]
        ghost_rgba = {cr, cg, cb, ghost_a}

        land
        |> Content.Tetris.Playing.piece_world_cells()
        |> Enum.filter(fn {_, r} -> r >= 2 end)
        |> Enum.reject(fn cell -> MapSet.member?(curr, cell) end)
        |> Enum.map(fn {c, r} -> cell_box(c, r, ghost_rgba) end)
      else
        []
      end

    active =
      if piece do
        piece
        |> Content.Tetris.Playing.piece_world_cells()
        |> Enum.filter(fn {_, r} -> r >= 2 end)
        |> Enum.map(fn {c, r} -> cell_box(c, r, colors[piece.kind]) end)
      else
        []
      end

    placed ++ ghost ++ active
  end

  defp cell_box(c, r, {cr, cg, cb, ca}) do
    {wx, wy, wz} = cell_world(c, r)
    h = @half
    {:box_3d, wx, wy + h, wz, h, h, {h, cr, cg, cb, ca}}
  end

  defp cell_world(c, r) do
    x = (c + 0.5 - Content.Tetris.Playing.cols() / 2) * @cell
    z = (r - Content.Tetris.Playing.rows() / 2 + 0.5) * @cell
    {x, 0.0, z}
  end

  defp next_piece_commands(kind, colors) do
    rots = Map.fetch!(Content.Tetris.Playing.tetromino_shapes(), kind)
    offsets = hd(rots)
    {cr, cg, cb, ca} = colors[kind]
    # Next piece: to the right of main board
    ox0 = 6.2
    oz0 = -3.0

    Enum.map(offsets, fn {dx, dy} ->
      x = ox0 + dx * @cell
      z = oz0 + dy * @cell
      h = @half * 0.85
      {:box_3d, x, h, z, h, h, {h, cr, cg, cb, ca}}
    end)
  end
end
