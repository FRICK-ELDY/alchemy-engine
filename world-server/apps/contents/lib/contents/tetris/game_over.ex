defmodule Content.Tetris.GameOver do
  @moduledoc """
  Game over; RETRY returns to play.
  """
  @behaviour Contents.SceneBehaviour

  @impl true
  def init(init_arg) do
    arg = init_arg || %{}
    {:ok, Map.take(arg, [:score, :lines])}
  end

  @impl true
  def render_type, do: :game_over

  @impl true
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      {:transition, {:replace, Content.Tetris.Playing, %{}}, %{state | retry: false}}
    else
      {:continue, state}
    end
  end
end
