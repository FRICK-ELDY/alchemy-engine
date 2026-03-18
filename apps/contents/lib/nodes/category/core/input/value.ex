defmodule Contents.Nodes.Category.Core.Input.Value do
  @moduledoc """
  定数値の入力ノード。`context[:value]` から値を取得して返す。

  `:value` が存在しない場合は `{:error, :missing_value}` を返す。
  後続ノード（Add, Equals 等）への nil 渡しによるクラッシュを防ぐ。

  典型的な値型: `Structs.Category.Value.Float.t/0`, `Structs.Category.Value.Int.t/0`, `Structs.Category.Value.Bool.t/0`, `Structs.Category.Text.String.t/0` 等。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  @spec handle_sample(map(), map() | nil) :: term() | {:error, :missing_value}
  def handle_sample(_inputs, context) do
    case Map.get(context || %{}, :value) do
      nil -> {:error, :missing_value}
      value -> value
    end
  end
end
