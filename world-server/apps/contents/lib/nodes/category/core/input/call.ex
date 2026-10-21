defmodule Contents.Nodes.Category.Core.Input.Call do
  @moduledoc """
  同期/非同期のアクション。Target の ref にパルスを送る。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_pulse(_pulse, _context), do: :ok
end
