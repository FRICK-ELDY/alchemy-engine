defmodule Contents.Nodes.Category.Core.Input.Display do
  @moduledoc """
  値を表示するための出力ノード。
  入力された value をそのまま表示する。

  入力値の型: `Structs.Category.Value.*`, `Structs.Category.Text.String.t/0` 等。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(map(), map()) :: map()
  def handle_sample(inputs, _context), do: inputs
end
