defmodule Contents.Nodes.Category.Operators.BoolVectors.All do
  @moduledoc """
  全要素が true かどうかを返す。
  要素は truthy/falsy として扱う（`nil` と `false` は falsy、それ以外は truthy）。

  戻り値: `Structs.Category.Value.Bool.t/0`。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(map(), map()) :: Structs.Category.Value.Bool.t()
  def handle_sample(%{input: input}, _context) when is_tuple(input) do
    Tuple.to_list(input) |> Enum.all?(& &1)
  end

  def handle_sample(_inputs, _context), do: false
end
