defmodule Contents.Nodes.Category.Time.Stopwatch do
  @moduledoc """
  ストップウォッチノード。経過時間の計測。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_pulse(_pulse, _context), do: :ok

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(_inputs, _context), do: nil
end
