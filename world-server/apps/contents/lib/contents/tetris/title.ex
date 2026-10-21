defmodule Content.Tetris.Title do
  @moduledoc """
  Title scene; START transitions to play.
  """
  @behaviour Contents.SceneBehaviour

  @impl true
  def init(_init_arg) do
    {:ok, %{start: false}}
  end

  @impl true
  def render_type, do: :title

  @impl true
  def update(_context, state) do
    if Map.get(state, :start, false) do
      {:transition, {:replace, Content.Tetris.Playing, %{}}, %{state | start: false}}
    else
      {:continue, state}
    end
  end
end
