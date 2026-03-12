defmodule Contents.Nodes.Category.Core.Input.Value do
  @moduledoc """
  定数値の入力ノード。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(_inputs, _context), do: nil
end
