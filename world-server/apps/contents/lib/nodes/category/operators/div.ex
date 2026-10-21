defmodule Contents.Nodes.Category.Operators.Div do
  @moduledoc """
  除算ノード。

  ゼロ除算（`b == 0` または `b == 0.0`）の場合は `0` を返す。
  不正な入力（非数値など）の場合は `{:error, :invalid_type}` を返す。
  Executor は戻り値が `{:error, _}` のとき、エラー扱いするか呼び出し側で判断すること。
  ゼロ除算を呼び出し側で検出したい場合は、`{:error, :division_by_zero}` を返す設計への変更を検討可。

  入出力の数値型: `Structs.Category.Value.Float.t/0`, `Structs.Category.Value.Int.t/0` 等。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(%{a: number(), b: number()}, map()) ::
          number() | {:error, :invalid_type}
  def handle_sample(%{a: a, b: b}, _context) when is_number(a) and is_number(b) do
    if b == 0 or b == 0.0, do: 0, else: a / b
  end

  def handle_sample(%{a: _a, b: _b}, _context), do: {:error, :invalid_type}
  def handle_sample(_inputs, _context), do: {:error, :invalid_type}
end
