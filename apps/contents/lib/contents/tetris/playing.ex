defmodule Content.Tetris.Scenes.Playing do
  @moduledoc """
  Tetris サンプルのプレイ中シーン。

  SimpleBox3D と同じく Elixir 側で状態を管理し、`build_frame/2` で 3D ボックス描画を組み立てる。
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

  @tick_sec 1.0 / 60.0
  @board_w 10
  @board_h 20
  @spawn_x 3
  @spawn_y 19

  @drop_interval_sec 0.55
  @soft_drop_interval_sec 0.08

  @cell_size 1.0
  @cell_half 0.46
  @board_center_x (@board_w - 1) / 2.0

  @camera_eye {0.0, 12.0, 25.0}
  @camera_target {0.0, 9.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 42.0
  @camera_near 0.1
  @camera_far 100.0

  @color_grid {0.22, 0.22, 0.26, 1.0}
  @color_sky_top {0.08, 0.08, 0.14, 1.0}
  @color_sky_bottom {0.02, 0.02, 0.05, 1.0}
  @color_ghost {0.85, 0.85, 0.9, 0.18}

  @shape_types [:i, :o, :t, :s, :z, :j, :l]

  @shape_colors %{
    i: {0.25, 0.95, 0.95, 1.0},
    o: {0.95, 0.9, 0.2, 1.0},
    t: {0.8, 0.35, 0.95, 1.0},
    s: {0.25, 0.9, 0.25, 1.0},
    z: {0.95, 0.28, 0.28, 1.0},
    j: {0.25, 0.45, 0.95, 1.0},
    l: {0.95, 0.58, 0.2, 1.0}
  }

  @line_scores %{1 => 100, 2 => 300, 3 => 500, 4 => 800}

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    origin = Transform.new()

    landing_object =
      ObjectStruct.new(name: "BoardAnchor", transform: %Transform{position: {0.0, 0.0, 0.0}})

    active_piece = spawn_piece()

    {:ok,
     %{
       origin: origin,
       landing_object: landing_object,
       board: %{},
       active_piece: active_piece,
       drop_acc_sec: 0.0,
       prev_input: {0.0, 0.0},
       score: 0,
       cleared_lines: 0,
       alive: valid_piece_position?(active_piece, %{})
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(context, state) do
    if Map.get(state, :alive, true) do
      room_id = Map.get(context, :room_id, :main)
      {dx, dz} = Contents.ComponentList.local_user_input_module().get_move_vector(room_id)
      state = handle_discrete_input(state, dx, dz)
      state = apply_gravity(state, dz)
      {:continue, state}
    else
      {:transition, {:replace, Content.Tetris.Scenes.GameOver, %{}}, state}
    end
  end

  def build_frame(playing_state, context) do
    content = Core.Config.current()
    current_scene = Map.get(context, :current_scene, content.playing_scene())

    commands = build_frame_commands(playing_state)
    camera = build_frame_camera()
    ui = build_frame_ui(current_scene, content, playing_state)
    {commands, camera, ui}
  end

  defp build_frame_commands(scene_state) do
    board = Map.get(scene_state, :board, %{})
    active_piece = Map.get(scene_state, :active_piece)

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
        size: 18.0,
        divisions: 18,
        color: {grid_r, grid_g, grid_b, grid_a}
      )[:vertices]

    grid_cmd = {:grid_plane_verts, grid_vertices}

    fixed_blocks =
      Enum.map(board, fn {{x, y}, color} ->
        block_command(x, y, color)
      end)

    active_blocks =
      if is_map(active_piece) do
        color = piece_color(active_piece.type)

        Enum.map(piece_cells(active_piece), fn {x, y} ->
          block_command(x, y, color)
        end)
      else
        []
      end

    ghost_blocks =
      if is_map(active_piece) do
        ghost = ghost_piece(active_piece, board)
        active_cells = MapSet.new(piece_cells(active_piece))

        ghost
        |> piece_cells()
        |> Enum.reject(&MapSet.member?(active_cells, &1))
        |> Enum.map(fn {x, y} ->
          block_command(x, y, @color_ghost)
        end)
      else
        []
      end

    [skybox_cmd, grid_cmd] ++ fixed_blocks ++ ghost_blocks ++ active_blocks
  end

  defp build_frame_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  defp build_frame_ui(current_scene, content, scene_state) do
    score = Map.get(scene_state, :score, 0)
    lines = Map.get(scene_state, :cleared_lines, 0)

    game_info =
      {:node, {:top_left, {24.0, 24.0}, :wrap}, {:vertical_layout, 6.0, {14.0, 12.0, 14.0, 12.0}},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:text, "TETRIS SAMPLE", {0.92, 0.95, 1.0, 1.0}, 26.0, true}, []},
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:text, "Score: #{score}", {0.86, 0.92, 1.0, 1.0}, 18.0, true}, []},
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:text, "Lines: #{lines}", {0.75, 0.8, 0.9, 1.0}, 15.0, false}, []},
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:text, "A/D: Move  W: Rotate  S: Drop", {0.66, 0.72, 0.84, 1.0}, 14.0, false}, []}
       ]}

    game_over_overlay =
      if current_scene == content.game_over_scene() do
        [
          {:node, {:center, {0.0, 0.0}, :wrap},
           {:rect, {0.14, 0.05, 0.05, 1.0}, 16.0, {{1.0, 0.35, 0.35, 1.0}, 2.0}},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 10.0, {56.0, 34.0, 56.0, 34.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "GAME OVER", {1.0, 0.5, 0.5, 1.0}, 40.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "Score: #{score}", {1.0, 0.98, 0.9, 1.0}, 20.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:button, "  RETRY  ", "__retry__", {0.84, 0.24, 0.24, 1.0}, 160.0, 44.0}, []}
              ]}
           ]}
        ]
      else
        []
      end

    {:canvas, [game_info | game_over_overlay]}
  end

  defp handle_discrete_input(state, dx, dz) do
    {prev_dx, prev_dz} = Map.get(state, :prev_input, {0.0, 0.0})
    board = state.board
    piece = state.active_piece

    piece =
      cond do
        dx <= -0.5 and prev_dx > -0.5 -> maybe_move(piece, board, -1, 0)
        dx >= 0.5 and prev_dx < 0.5 -> maybe_move(piece, board, 1, 0)
        true -> piece
      end

    piece =
      if dz <= -0.5 and prev_dz > -0.5 do
        maybe_rotate(piece, board)
      else
        piece
      end

    %{state | active_piece: piece, prev_input: {dx, dz}}
  end

  defp apply_gravity(state, dz) do
    drop_interval_sec = if dz >= 0.5, do: @soft_drop_interval_sec, else: @drop_interval_sec
    next_acc = state.drop_acc_sec + @tick_sec

    if next_acc >= drop_interval_sec do
      state
      |> Map.put(:drop_acc_sec, 0.0)
      |> step_fall()
    else
      %{state | drop_acc_sec: next_acc}
    end
  end

  defp step_fall(state) do
    board = state.board
    piece = state.active_piece
    moved = %{piece | y: piece.y - 1}

    if valid_piece_position?(moved, board) do
      %{state | active_piece: moved}
    else
      lock_piece_and_spawn_next(state)
    end
  end

  defp lock_piece_and_spawn_next(state) do
    merged_board =
      Enum.reduce(piece_cells(state.active_piece), state.board, fn {x, y}, acc ->
        if y >= 0 and y < @board_h do
          Map.put(acc, {x, y}, piece_color(state.active_piece.type))
        else
          acc
        end
      end)

    {cleared_board, cleared_count} = clear_lines(merged_board)
    score_gain = Map.get(@line_scores, cleared_count, 0)
    next_piece = spawn_piece()
    alive = valid_piece_position?(next_piece, cleared_board)

    %{
      state
      | board: cleared_board,
        active_piece: next_piece,
        score: state.score + score_gain,
        cleared_lines: state.cleared_lines + cleared_count,
        alive: alive
    }
  end

  defp clear_lines(board) do
    full_rows =
      0..(@board_h - 1)
      |> Enum.filter(fn y ->
        Enum.all?(0..(@board_w - 1), fn x -> Map.has_key?(board, {x, y}) end)
      end)

    if full_rows == [] do
      {board, 0}
    else
      rows = MapSet.new(full_rows)

      shifted =
        Enum.reduce(board, %{}, fn {{x, y}, color}, acc ->
          if MapSet.member?(rows, y) do
            acc
          else
            shift_down = Enum.count(full_rows, &(&1 < y))
            Map.put(acc, {x, y - shift_down}, color)
          end
        end)

      {shifted, length(full_rows)}
    end
  end

  defp maybe_move(piece, board, dx, dy) do
    candidate = %{piece | x: piece.x + dx, y: piece.y + dy}
    if valid_piece_position?(candidate, board), do: candidate, else: piece
  end

  defp maybe_rotate(piece, board) do
    candidate = %{piece | rot: rem(piece.rot + 1, 4)}

    cond do
      valid_piece_position?(candidate, board) ->
        candidate

      valid_piece_position?(%{candidate | x: candidate.x - 1}, board) ->
        %{candidate | x: candidate.x - 1}

      valid_piece_position?(%{candidate | x: candidate.x + 1}, board) ->
        %{candidate | x: candidate.x + 1}

      true ->
        piece
    end
  end

  defp valid_piece_position?(piece, board) do
    Enum.all?(piece_cells(piece), fn {x, y} ->
      x >= 0 and x < @board_w and y >= 0 and (y >= @board_h or not Map.has_key?(board, {x, y}))
    end)
  end

  defp ghost_piece(piece, board) do
    Stream.iterate(piece, fn p -> %{p | y: p.y - 1} end)
    |> Enum.reduce_while(piece, fn candidate, _acc ->
      if valid_piece_position?(candidate, board) do
        {:cont, candidate}
      else
        {:halt, %{candidate | y: candidate.y + 1}}
      end
    end)
  end

  defp spawn_piece do
    type = Enum.random(@shape_types)
    %{type: type, rot: 0, x: @spawn_x, y: @spawn_y}
  end

  defp piece_color(type), do: Map.fetch!(@shape_colors, type)

  defp block_command(x, y, {r, g, b, a}) do
    world_x = (x - @board_center_x) * @cell_size
    world_y = (y + 0.5) * @cell_size
    world_z = 0.0
    {:box_3d, world_x, world_y, world_z, @cell_half, @cell_half, {@cell_half, r, g, b, a}}
  end

  defp piece_cells(%{type: type, rot: rot, x: px, y: py}) do
    base_cells = shape_cells(type, rot)
    Enum.map(base_cells, fn {x, y} -> {px + x, py + y} end)
  end

  defp shape_cells(:i, rot) do
    case rem(rot, 4) do
      0 -> [{0, 1}, {1, 1}, {2, 1}, {3, 1}]
      1 -> [{2, 0}, {2, 1}, {2, 2}, {2, 3}]
      2 -> [{0, 2}, {1, 2}, {2, 2}, {3, 2}]
      _ -> [{1, 0}, {1, 1}, {1, 2}, {1, 3}]
    end
  end

  defp shape_cells(:o, _rot), do: [{1, 0}, {2, 0}, {1, 1}, {2, 1}]

  defp shape_cells(:t, rot) do
    case rem(rot, 4) do
      0 -> [{1, 1}, {0, 0}, {1, 0}, {2, 0}]
      1 -> [{1, 1}, {1, 0}, {1, 2}, {2, 1}]
      2 -> [{1, 1}, {0, 1}, {1, 2}, {2, 1}]
      _ -> [{1, 1}, {1, 0}, {1, 2}, {0, 1}]
    end
  end

  defp shape_cells(:s, rot) do
    case rem(rot, 4) do
      0 -> [{1, 1}, {2, 1}, {0, 0}, {1, 0}]
      1 -> [{1, 0}, {1, 1}, {2, 1}, {2, 2}]
      2 -> [{1, 2}, {2, 2}, {0, 1}, {1, 1}]
      _ -> [{0, 0}, {0, 1}, {1, 1}, {1, 2}]
    end
  end

  defp shape_cells(:z, rot) do
    case rem(rot, 4) do
      0 -> [{0, 1}, {1, 1}, {1, 0}, {2, 0}]
      1 -> [{2, 0}, {2, 1}, {1, 1}, {1, 2}]
      2 -> [{0, 2}, {1, 2}, {1, 1}, {2, 1}]
      _ -> [{1, 0}, {1, 1}, {0, 1}, {0, 2}]
    end
  end

  defp shape_cells(:j, rot) do
    case rem(rot, 4) do
      0 -> [{0, 1}, {0, 0}, {1, 0}, {2, 0}]
      1 -> [{1, 0}, {2, 0}, {1, 1}, {1, 2}]
      2 -> [{0, 2}, {1, 2}, {2, 2}, {2, 1}]
      _ -> [{1, 0}, {1, 1}, {1, 2}, {0, 2}]
    end
  end

  defp shape_cells(:l, rot) do
    case rem(rot, 4) do
      0 -> [{2, 1}, {0, 0}, {1, 0}, {2, 0}]
      1 -> [{1, 0}, {1, 1}, {1, 2}, {2, 2}]
      2 -> [{0, 2}, {1, 2}, {2, 2}, {0, 1}]
      _ -> [{0, 0}, {1, 0}, {1, 1}, {1, 2}]
    end
  end
end
