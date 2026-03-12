defmodule Contents.Nodes.Category.Operators.BoolVectors.Any do
  @moduledoc """
  いずれかの要素が true かどうかを返す。
  要素は truthy/falsy として扱う（`nil` と `false` は falsy、それ以外は truthy）。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{input: input}, _context) when is_tuple(input) do
    Tuple.to_list(input) |> Enum.any?(& &1)
  end

  def handle_sample(_inputs, _context), do: false
end
