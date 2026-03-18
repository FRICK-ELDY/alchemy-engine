defmodule Contents.Nodes.Category.Operators.BoolVectors.XorElements do
  @moduledoc """
  要素間の XOR 集約。要素は truthy/falsy として扱う（all/any/none と同様）。

  戻り値: `Structs.Category.Value.Bool.t/0`。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(map(), map()) :: Structs.Category.Value.Bool.t()
  def handle_sample(%{input: input}, _context) when is_tuple(input) do
    Tuple.to_list(input)
    |> Enum.reduce(false, fn x, acc -> to_bool(x) != acc end)
  end

  def handle_sample(_inputs, _context), do: false

  defp to_bool(nil), do: false
  defp to_bool(false), do: false
  defp to_bool(_), do: true
end
