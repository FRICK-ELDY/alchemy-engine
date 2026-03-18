defmodule Contents.Nodes.Category.Time.Stopwatch do
  @moduledoc """
  ストップウォッチノード。経過時間の計測。

  経過時間の表現には `Structs.Category.Time.TimeSpan.t/0` 等の利用を想定。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_pulse(_pulse, _context), do: :ok

  @impl Contents.Behaviour.Nodes
  def handle_sample(_inputs, _context), do: nil
end
