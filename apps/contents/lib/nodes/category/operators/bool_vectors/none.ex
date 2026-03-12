defmodule Contents.Nodes.Category.Operators.BoolVectors.None do
  @moduledoc """
  全要素が false かどうかを返す。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{input: input}, _context) when is_tuple(input) do
    Tuple.to_list(input) |> Enum.all?(&(!&1))
  end

  def handle_sample(_inputs, _context), do: true
end
