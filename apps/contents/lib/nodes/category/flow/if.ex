defmodule Contents.Nodes.Category.Flow.If do
  @moduledoc """
  条件分岐ノード。logic in の条件に応じて action out を選択する。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_pulse(_pulse, _context), do: :ok

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(inputs, _context), do: inputs
end
