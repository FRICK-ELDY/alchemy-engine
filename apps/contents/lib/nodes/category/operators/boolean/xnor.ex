defmodule Contents.Nodes.Category.Operators.Boolean.Xnor do
  @moduledoc """
  排他的論理和の否定。`a` と `b` は boolean を期待。非 boolean は truthy/falsy として扱う。

  入出力: `Structs.Category.Value.Bool.t/0`。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(map(), map()) :: Structs.Category.Value.Bool.t()
  def handle_sample(%{a: a, b: b}, _context), do: to_bool(a) == to_bool(b)
  def handle_sample(_inputs, _context), do: true

  defp to_bool(nil), do: false
  defp to_bool(false), do: false
  defp to_bool(_), do: true
end
