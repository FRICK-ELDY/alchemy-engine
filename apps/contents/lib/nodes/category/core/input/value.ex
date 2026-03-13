defmodule Contents.Nodes.Category.Core.Input.Value do
  @moduledoc """
  定数値の入力ノード。`context[:value]` から値を取得して返す。

  `:value` が存在しない場合は `{:error, :missing_value}` を返す。
  後続ノード（Add, Equals 等）への nil 渡しによるクラッシュを防ぐ。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(_inputs, context) do
    case Map.get(context || %{}, :value) do
      nil -> {:error, :missing_value}
      value -> value
    end
  end
end
