defmodule Contents.Nodes.Category.Core.Input.Call do
  @moduledoc """
  同期/非同期のアクション。Target の ref にパルスを送る。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_pulse(_pulse, _context), do: :ok
end
