defmodule Contents.Nodes.Category.Operators.Add do
  @moduledoc """
  加算ノード。`a` と `b` は数値である必要がある。
  非数値の場合は `{:error, :invalid_type}` を返す。
  Executor は戻り値が `{:error, _}` のとき、エラー扱いするか呼び出し側で判断すること。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_sample(%{a: a, b: b}, _context) when is_number(a) and is_number(b), do: a + b
  def handle_sample(%{a: _a, b: _b}, _context), do: {:error, :invalid_type}
  def handle_sample(_inputs, _context), do: {:error, :invalid_type}
end
