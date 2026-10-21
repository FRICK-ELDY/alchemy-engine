defmodule Contents.Nodes.Category.Actions.Write do
  @moduledoc """
  action in port にパルスを受け取ったとき動作。
  logic in からデータを吸い上げ、対象を書き換え。終了後 action out へパルスを返す。

  logic の値型: `Structs.Category.Value.*`, `Structs.Category.Text.String.t/0` 等。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_pulse(_pulse, _context), do: :ok
end
