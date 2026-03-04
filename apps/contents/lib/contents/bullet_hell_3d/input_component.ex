defmodule Content.BulletHell3D.InputComponent do
  @moduledoc """
  ウィンドウからの移動入力を受け取り、Playing シーン state に反映するコンポーネント。

  Rust 物理エンジンを使わない BulletHell3D では、winit からの
  `{:move_input, dx, dy}` メッセージを直接シーン state に書き込む。
  `GameEvents` は `{:move_input, dx, dy}` を受信すると `on_event/2` として
  各コンポーネントに配信するため、ここで `SceneManager` を更新する。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:move_input, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    Core.SceneManager.update_by_module(
      Content.BulletHell3D.Scenes.Playing,
      fn state -> Map.put(state, :move_input, {dx, dy}) end
    )

    :ok
  end

  def on_event({:ui_action, "__retry__"}, _context) do
    Core.SceneManager.update_by_module(
      Content.BulletHell3D.Scenes.GameOver,
      fn state -> Map.put(state, :retry, true) end
    )

    :ok
  end

  def on_event(_event, _context), do: :ok
end
