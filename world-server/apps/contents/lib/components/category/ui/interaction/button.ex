defmodule Contents.Components.Category.UI.Interaction.Button do
  @moduledoc """
  ボタン操作コンポーネント。クリック・タッチ等の入力イベントを受信する。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
