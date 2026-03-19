defmodule Contents.Components.Category.Device.Mouse do
  @moduledoc """
  マウス由来の入力のみを扱うデバイスコンポーネント。

  ## 処理するイベント
  - `{:move_input, dx, dz}` — WASD 移動入力ベクトル（同一クライアント入力としてマウスと共に扱う）
  - `{:mouse_delta, dx, dy}` — マウス移動量（カーソルグラブ中のみ Rust 側から送信される）
  """
  @behaviour Core.Component

  alias Contents.Components.Category.Device.Helpers

  @impl Core.Component
  def on_event({:move_input, dx, dz}, _context) when is_float(dx) and is_float(dz) do
    Helpers.with_playing_scene(fn state ->
      Map.put(state, :move_input, {dx, dz})
    end)

    :ok
  end

  def on_event({:mouse_delta, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    Helpers.with_playing_scene(fn state ->
      Map.put(state, :mouse_delta, {dx, dy})
    end)

    :ok
  end

  def on_event(_event, _context), do: :ok
end
