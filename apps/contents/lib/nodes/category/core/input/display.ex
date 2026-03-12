defmodule Contents.Nodes.Category.Core.Input.Display do
  @moduledoc """
  値を表示するための出力ノード。
  入力された value をそのまま表示する。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(inputs, _context), do: inputs
end
