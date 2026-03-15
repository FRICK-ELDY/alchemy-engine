defmodule Contents.Nodes.Category.Operators.Equals do
  @moduledoc """
  比較ノード（equals, greater, less 等）。

  `op` は `:eq`, `:ne`, `:gt`, `:ge`, `:lt`, `:le` を期待する。
  想定外の `op` の場合は `:eq` 相当（`a == b`）でフォールバックする。

  `a` または `b` が nil あるいは比較不可能な型の場合は `{:error, :invalid_type}` を返す。
  Add/Sub と同じく、呼び出し側でエラー扱いするか判断する。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_sample(%{a: a, b: b, op: op}, _context) when op in [:gt, :ge, :lt, :le] do
    if comparable?(a, b) do
      case op do
        :gt -> a > b
        :ge -> a >= b
        :lt -> a < b
        :le -> a <= b
      end
    else
      {:error, :invalid_type}
    end
  end

  def handle_sample(%{a: a, b: b, op: op}, _context) when op in [:eq, :ne] do
    case op do
      :eq -> a == b
      :ne -> a != b
    end
  end

  def handle_sample(%{a: a, b: b, op: _op}, _context), do: a == b
  def handle_sample(%{a: a, b: b}, _context), do: a == b
  def handle_sample(_inputs, _context), do: {:error, :invalid_type}

  defp comparable?(a, b) when is_number(a) and is_number(b), do: true
  defp comparable?(a, b) when is_binary(a) and is_binary(b), do: true
  defp comparable?(a, b) when is_atom(a) and is_atom(b), do: true
  defp comparable?(nil, _), do: false
  defp comparable?(_, nil), do: false
  defp comparable?(_a, _b), do: false
end
