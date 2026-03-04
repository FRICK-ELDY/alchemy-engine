defmodule Content.CanvasTest.InputComponent do
  @moduledoc """
  ウィンドウからの入力イベントを受け取り、Playing シーン state に反映するコンポーネント。

  ## 処理するイベント
  - `{:move_input, dx, dz}` — WASD 移動入力ベクトル
  - `{:mouse_delta, dx, dy}` — マウス移動量（カーソルグラブ中のみ Rust 側から送信される）
  - `{:sprint, bool}` — 左 Shift キー押下状態
  - `{:key_pressed, :escape}` — HUD 表示トグル（グラブ中・解放中どちらでも届く）
  - `{:ui_action, "__quit__"}` — ウィンドウ終了

  ## カーソルグラブの仕組み
  - ウィンドウクリック → Rust 側でカーソルをキャプチャ（非表示・ロック）
  - Escape（常に Elixir へ通知）:
    - HUD非表示時: HUDを表示してカーソル解放（HUD操作モードへ）
    - HUD表示中: HUDを閉じてカーソルをグラブ（ゲームモードへ戻る）
  - グラブ/解放要求は `cursor_grab_request` として Playing 状態に書き込み、
    RenderComponent が次フレームで Rust へ送信する
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:move_input, dx, dz}, _context) when is_float(dx) and is_float(dz) do
    Core.SceneManager.update_by_module(
      Content.CanvasTest.Scenes.Playing,
      fn state -> Map.put(state, :move_input, {dx, dz}) end
    )

    :ok
  end

  def on_event({:mouse_delta, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    Core.SceneManager.update_by_module(
      Content.CanvasTest.Scenes.Playing,
      fn state -> Map.put(state, :mouse_delta, {dx, dy}) end
    )

    :ok
  end

  def on_event({:sprint, value}, _context) when is_boolean(value) do
    Core.SceneManager.update_by_module(
      Content.CanvasTest.Scenes.Playing,
      fn state -> Map.put(state, :sprint, value) end
    )

    :ok
  end

  def on_event({:key_pressed, :escape}, _context) do
    Core.SceneManager.update_by_module(
      Content.CanvasTest.Scenes.Playing,
      fn state ->
        if state.hud_visible do
          # HUD表示中: HUDを閉じてカーソルをグラブ（ゲームに戻る）
          state
          |> Map.put(:hud_visible, false)
          |> Map.put(:cursor_grab_request, :grab)
        else
          # HUD非表示: HUDを表示してカーソルを解放（HUDを操作できる状態へ）
          state
          |> Map.put(:hud_visible, true)
          |> Map.put(:cursor_grab_request, :release)
        end
      end
    )

    :ok
  end

  def on_event({:ui_action, "__quit__"}, _context) do
    System.stop(0)
    :ok
  end

  def on_event(_event, _context), do: :ok
end
