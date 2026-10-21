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
  def on_event({:move_input, dx, dz}, context) when is_float(dx) and is_float(dz) do
    with_room(context, fn room_id ->
      Helpers.with_playing_scene(room_id, fn state ->
        Map.put(state, :move_input, {dx, dz})
      end)
    end)

    :ok
  end

  def on_event({:mouse_delta, dx, dy}, context) when is_float(dx) and is_float(dy) do
    with_room(context, fn room_id ->
      Helpers.with_playing_scene(room_id, fn state ->
        Map.put(state, :mouse_delta, {dx, dy})
      end)
    end)

    :ok
  end

  def on_event(_event, _context), do: :ok

  defp with_room(context, fun) do
    case Map.get(context, :room_id) do
      nil -> :ok
      room_id -> fun.(room_id)
    end
  end
end
