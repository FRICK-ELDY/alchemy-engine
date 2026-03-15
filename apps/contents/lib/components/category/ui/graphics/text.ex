defmodule Contents.Components.Category.UI.Graphics.Text do
  @moduledoc """
  テキスト描画コンポーネント。文字列を画面に表示する。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
