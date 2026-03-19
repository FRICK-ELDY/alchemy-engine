defmodule Contents.Objects.Components.Noop do
  @moduledoc """
  Object に紐づく Component のサンプル実装（検証用）。

  FormulaTest / CanvasTest 等で User Object に付与し、
  Struct → Node → Component → Object の紐づきを検証する。
  run/2 では Node を呼ばず最小限の実装とする。
  """
  @behaviour Contents.Behaviour.ObjectComponent

  @impl Contents.Behaviour.ObjectComponent
  def run(_object, _context), do: :ok
end
