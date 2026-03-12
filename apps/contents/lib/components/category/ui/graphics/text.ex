defmodule Contents.Components.Category.UI.Graphics.Text do
  @moduledoc """
  テキスト描画コンポーネント。文字列を画面に表示する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
