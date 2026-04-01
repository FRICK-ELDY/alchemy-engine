defmodule Content.Tetris.Playing do
  @moduledoc """
  Tetris play scene: 10x22 grid (2 hidden rows at top), 7 tetrominoes, line clears and score.
  """
  @behaviour Contents.SceneBehaviour

  @cols 10
  @rows 22
  @visible_rows 20
  @tick_sec 1.0 / 60.0

  # Base drop interval (frames) at level 1
  @base_drop_frames 45
  @h_repeat_frames 8
  @rotate_cooldown_frames 12

  @pieces [:i, :o, :t, :s, :z, :j, :l]

  # Colors {r,g,b,a}
  @colors %{
    i: {0.2, 0.85, 0.95, 1.0},
    o: {0.95, 0.85, 0.15, 1.0},
    t: {0.65, 0.25, 0.85, 1.0},
    s: {0.25, 0.85, 0.35, 1.0},
    z: {0.9, 0.2, 0.2, 1.0},
    j: {0.2, 0.35, 0.95, 1.0},
    l: {0.95, 0.55, 0.15, 1.0},
    ghost: {0.35, 0.35, 0.4, 0.45}
  }

  @impl true
  def init(_init_arg) do
    {:ok, new_game_state()}
  end

  @impl true
  def render_type, do: :playing

  @impl true
  def update(_context, state) do
    state = tick(state)

    if Map.get(state, :game_over, false) do
      {:transition,
       {:replace, Content.Tetris.GameOver,
        %{score: state.score, lines: state.lines_cleared_total}}, state}
    else
      {:continue, state}
    end
  end

  defp new_game_state do
    bag = Enum.shuffle(@pieces)
    {piece, bag} = pop_bag(bag)

    %{
      grid: %{},
      current: spawn_piece(piece),
      next_kind: peek_next(bag),
      bag: bag,
      score: 0,
      lines_cleared_total: 0,
      level: 1,
      drop_frames: @base_drop_frames,
      drop_timer: @base_drop_frames,
      h_cool: 0,
      rotate_cool: 0,
      game_over: false,
      move_input: {0.0, 0.0}
    }
  end

  defp pop_bag(bag) do
    case bag do
      [] -> pop_bag(Enum.shuffle(@pieces))
      [a | rest] -> {a, rest}
    end
  end

  defp peek_next(bag) do
    case bag do
      [] -> hd(Enum.shuffle(@pieces))
      [a | _] -> a
    end
  end

  defp spawn_piece(kind) do
    ox = 3
    oy = 0
    %{kind: kind, rot: 0, x: ox, y: oy}
  end

  defp tick(state) do
    {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
    dx_i = trunc(dx)
    dz_i = trunc(dz)

    state = %{state | h_cool: max(0, state.h_cool - 1), rotate_cool: max(0, state.rotate_cool - 1)}

    state =
      cond do
        dx_i < 0 and state.h_cool == 0 ->
          case try_shift(state, -1, 0) do
            {:ok, s} -> %{s | h_cool: @h_repeat_frames}
            :no -> state
          end

        dx_i > 0 and state.h_cool == 0 ->
          case try_shift(state, 1, 0) do
            {:ok, s} -> %{s | h_cool: @h_repeat_frames}
            :no -> state
          end

        true ->
          state
      end

    # W / arrow up: rotate
    state =
      if dz_i < 0 and state.rotate_cool == 0 do
        case try_rotate(state) do
          {:ok, s} -> %{s | rotate_cool: @rotate_cooldown_frames}
          :no -> state
        end
      else
        state
      end

    # S / arrow down: soft drop (one row per frame)
    state =
      if dz_i > 0 do
        case try_shift(state, 0, 1) do
          {:ok, s} -> %{s | score: s.score + 1}
          :no -> lock_and_continue(state)
        end
      else
        state
      end

    # Gravity
    state =
      if dz_i > 0 do
        state
      else
        drop_every = state.drop_frames
        new_timer = state.drop_timer - 1

        if new_timer <= 0 do
          case try_shift(state, 0, 1) do
            {:ok, s} -> %{s | drop_timer: drop_every}
            :no -> lock_and_continue(%{state | drop_timer: drop_every})
          end
        else
          %{state | drop_timer: new_timer}
        end
      end

    state
  end

  defp lock_and_continue(state) do
    {grid, score_add, lines} = merge_piece(state.grid, state.current)
    new_lines_total = state.lines_cleared_total + lines
    level = 1 + div(new_lines_total, 10)

    drop_frames =
      max(8, @base_drop_frames - (level - 1) * 3)

    {kind, bag} = pop_bag(state.bag)
    next_next = peek_next(bag)
    new_piece = spawn_piece(kind)

    game_over = not valid_placement?(grid, new_piece)

    if game_over do
      %{state | grid: grid, score: state.score + score_add, lines_cleared_total: new_lines_total, game_over: true}
    else
      %{
        state
        | grid: grid,
          score: state.score + score_add,
          lines_cleared_total: new_lines_total,
          level: level,
          drop_frames: drop_frames,
          drop_timer: drop_frames,
          current: new_piece,
          next_kind: next_next,
          bag: bag
      }
    end
  end

  defp try_shift(state, dx, dy) do
    cur = %{state.current | x: state.current.x + dx, y: state.current.y + dy}

    if valid_placement?(state.grid, cur) do
      {:ok, %{state | current: cur}}
    else
      :no
    end
  end

  defp try_rotate(state) do
    cur = state.current
    new_rot = rem(cur.rot + 1, 4)
    rotated = %{cur | rot: new_rot}

    tries = [{0, 0}, {-1, 0}, {1, 0}, {0, -1}, {-2, 0}, {2, 0}]

    Enum.reduce_while(tries, :no, fn {kx, ky}, _ ->
      cand = %{rotated | x: rotated.x + kx, y: rotated.y + ky}

      if valid_placement?(state.grid, cand) do
        {:halt, {:ok, %{state | current: cand}}}
      else
        {:cont, :no}
      end
    end)
  end

  defp valid_placement?(grid, piece) do
    cells = piece_cells(piece)

    Enum.all?(cells, fn {cx, cy} ->
      cx >= 0 and cx < @cols and cy >= 0 and cy < @rows and grid[{cx, cy}] == nil
    end)
  end

  @doc """
  Returns the piece lowered until it cannot move down further (hard-drop landing pose).
  Used for ghost rendering. If `piece` is invalid on `grid`, returns `piece` unchanged.
  """
  def landing_piece(grid, piece) do
    if valid_placement?(grid, piece) do
      drop_until_land(grid, piece)
    else
      piece
    end
  end

  defp drop_until_land(grid, piece) do
    next = %{piece | y: piece.y + 1}

    if valid_placement?(grid, next) do
      drop_until_land(grid, next)
    else
      piece
    end
  end

  defp merge_piece(grid, piece) do
    color = piece.kind

    grid =
      Enum.reduce(piece_cells(piece), grid, fn {cx, cy}, g ->
        Map.put(g, {cx, cy}, color)
      end)

    {cleared_grid, n} = clear_lines(grid)
    {cleared_grid, line_clear_score(n), n}
  end

  defp clear_lines(grid) do
    full_rows =
      for r <- 0..(@rows - 1),
          Enum.all?(0..(@cols - 1), fn c -> Map.get(grid, {c, r}) != nil end),
          do: r

    if full_rows == [] do
      {grid, 0}
    else
      n = length(full_rows)

      new_grid =
        Enum.reduce(grid, %{}, fn {{c, r}, color}, acc ->
          if r in full_rows do
            acc
          else
            drop = Enum.count(full_rows, &(&1 > r))
            nr = r + drop
            if nr < @rows, do: Map.put(acc, {c, nr}, color), else: acc
          end
        end)

      {new_grid, n}
    end
  end

  defp line_clear_score(0), do: 0
  defp line_clear_score(1), do: 100
  defp line_clear_score(2), do: 300
  defp line_clear_score(3), do: 500
  defp line_clear_score(_n), do: 800

  defp piece_cells(piece) do
    offsets = shape_offsets(piece.kind, piece.rot)

    Enum.map(offsets, fn {ox, oy} ->
      {piece.x + ox, piece.y + oy}
    end)
  end

  defp shape_offsets(kind, rot) do
    rots = Map.fetch!(tetromino_shapes(), kind)
    Enum.at(rots, rot)
  end

  @doc false
  def tetromino_shapes do
    %{
      i: [
        [{0, 0}, {1, 0}, {2, 0}, {3, 0}],
        [{1, 0}, {1, 1}, {1, 2}, {1, 3}],
        [{0, 1}, {1, 1}, {2, 1}, {3, 1}],
        [{0, 0}, {0, 1}, {0, 2}, {0, 3}]
      ],
      o: [
        [{0, 0}, {1, 0}, {0, 1}, {1, 1}],
        [{0, 0}, {1, 0}, {0, 1}, {1, 1}],
        [{0, 0}, {1, 0}, {0, 1}, {1, 1}],
        [{0, 0}, {1, 0}, {0, 1}, {1, 1}]
      ],
      t: [
        [{1, 0}, {0, 1}, {1, 1}, {2, 1}],
        [{1, 0}, {1, 1}, {2, 1}, {1, 2}],
        [{0, 1}, {1, 1}, {2, 1}, {1, 2}],
        [{1, 0}, {0, 1}, {1, 1}, {1, 2}]
      ],
      s: [
        [{1, 0}, {2, 0}, {0, 1}, {1, 1}],
        [{1, 0}, {1, 1}, {2, 1}, {2, 2}],
        [{1, 1}, {2, 1}, {0, 2}, {1, 2}],
        [{0, 0}, {0, 1}, {1, 1}, {1, 2}]
      ],
      z: [
        [{0, 0}, {1, 0}, {1, 1}, {2, 1}],
        [{2, 0}, {1, 1}, {2, 1}, {1, 2}],
        [{0, 1}, {1, 1}, {1, 2}, {2, 2}],
        [{1, 0}, {0, 1}, {1, 1}, {0, 2}]
      ],
      j: [
        [{0, 0}, {0, 1}, {1, 1}, {2, 1}],
        [{1, 0}, {1, 1}, {1, 2}, {2, 0}],
        [{0, 1}, {1, 1}, {2, 1}, {2, 2}],
        [{0, 2}, {1, 0}, {1, 1}, {1, 2}]
      ],
      l: [
        [{2, 0}, {0, 1}, {1, 1}, {2, 1}],
        [{1, 0}, {2, 1}, {1, 1}, {1, 2}],
        [{0, 1}, {1, 1}, {2, 1}, {0, 2}],
        [{1, 0}, {1, 1}, {0, 2}, {1, 2}]
      ]
    }
  end

  @doc false
  def piece_world_cells(piece) do
    piece_cells(piece)
  end

  @doc false
  def visible_rows, do: @visible_rows

  @doc false
  def cols, do: @cols

  @doc false
  def rows, do: @rows

  @doc false
  def tick_sec, do: @tick_sec

  @doc false
  def colors, do: @colors
end
