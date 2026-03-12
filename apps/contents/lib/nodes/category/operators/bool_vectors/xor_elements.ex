defmodule Contents.Nodes.Category.Operators.BoolVectors.XorElements do
  @moduledoc """
  要素間の XOR 集約。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{input: input}, _context) when is_tuple(input) do
    Tuple.to_list(input)
    |> Enum.reduce(false, fn x, acc -> (x and not acc) or (not x and acc) end)
  end

  def handle_sample(_inputs, _context), do: false
end
