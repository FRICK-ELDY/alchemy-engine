defmodule Contents.Nodes.Category.Operators.Boolean.Xor do
  @moduledoc """
  排他的論理和。`a` と `b` は boolean を期待。非 boolean は truthy/falsy として扱う。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: to_bool(a) != to_bool(b)

  def handle_sample(_inputs, _context), do: false

  defp to_bool(nil), do: false
  defp to_bool(false), do: false
  defp to_bool(_), do: true
end
