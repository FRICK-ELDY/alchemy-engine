defmodule Content.VRTest.InputComponent do
  @moduledoc """
  VRTest の入力処理コンポーネント。

  Phase A: マウスドラッグでカメラ回転。
  - `{:mouse_delta, dx, dy}` — カメラの yaw / pitch を更新
  - `{:move_input, dx, dy}` — WASD 移動入力
  - `{:key_pressed, :escape}` — カーソルグラブのトグル
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:mouse_delta, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.VRTest.Scenes.Playing,
        fn state ->
          yaw = Map.get(state, :camera_yaw, 0.0) - dx * 0.002
          pitch = Map.get(state, :camera_pitch, 0.0) - dy * 0.002
          pitch_clamped = max(-1.4, min(1.4, pitch))

          state
          |> Map.put(:camera_yaw, yaw)
          |> Map.put(:camera_pitch, pitch_clamped)
        end
      )
    end

    :ok
  end

  def on_event({:move_input, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.VRTest.Scenes.Playing,
        fn state -> Map.put(state, :move_input, {dx, dy}) end
      )
    end

    :ok
  end

  def on_event({:key_pressed, :escape}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.VRTest.Scenes.Playing,
        fn state ->
          grabbed = Map.get(state, :cursor_grabbed, false)
          Map.put(state, :cursor_grab_request, if(grabbed, do: :release, else: :grab))
        end
      )
    end

    :ok
  end

  def on_event({:ui_action, "__retry__"}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.VRTest.Scenes.GameOver,
        fn state -> Map.put(state, :retry, true) end
      )
    end

    :ok
  end

  def on_event(_event, _context), do: :ok
end
