defmodule Contents.Components.Category.UI.Interaction.Button do
  @moduledoc """
  ボタン操作コンポーネント。クリック・タッチ等の入力イベントを受信する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
