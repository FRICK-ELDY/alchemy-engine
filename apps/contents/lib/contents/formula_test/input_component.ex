defmodule Content.FormulaTest.InputComponent do
  @moduledoc """
  FormulaTest の入力コンポーネント。

  - ESC: HUD 表示トグル
  - __quit__: ウィンドウ終了
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:key_pressed, :escape}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &toggle_hud/1
      )
    end

    :ok
  end

  def on_event({:ui_action, "__quit__"}, _context) do
    System.stop(0)
    :ok
  end

  def on_event(_event, _context), do: :ok

  defp toggle_hud(state) do
    hud_visible = not state.hud_visible
    cursor_grab = if hud_visible, do: :release, else: :grab

    state
    |> Map.put(:hud_visible, hud_visible)
    |> Map.put(:cursor_grab_request, cursor_grab)
  end
end
