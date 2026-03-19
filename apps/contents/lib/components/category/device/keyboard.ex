defmodule Contents.Components.Category.Device.Keyboard do
  @moduledoc """
  キーボード・UI アクションを扱うデバイスコンポーネント。

  ## 処理するイベント
  - `{:sprint, bool}` — 左 Shift キー押下状態
  - `{:key_pressed, :escape}` — HUD 表示トグル（グラブ中・解放中どちらでも届く）
  - `{:ui_action, "__quit__"}` — 終了要求（実行は上位層に委譲。イベント送信のみ）
  - `{:ui_action, "__retry__"}` — リトライ要求（game_over シーン state に retry: true を設定）

  ## 終了の委譲
  `__quit__` を受け取った場合、`System.stop/1` は呼ばない。
  イベントハンドラ（Game プロセス）に `:quit_requested` を送信し、
  実際の終了は上位層が行う。

  ## 制約
  `event_handler/1` が nil（イベントハンドラ未起動）の場合、
  `:quit_requested` は送信されず終了しない。仕様として許容する。
  """
  @behaviour Core.Component

  alias Contents.Components.Category.Device.Helpers

  @impl Core.Component
  def on_event({:sprint, value}, _context) when is_boolean(value) do
    Helpers.with_playing_scene(fn state ->
      Map.put(state, :sprint, value)
    end)

    :ok
  end

  def on_event({:key_pressed, :escape}, _context) do
    Helpers.with_playing_scene(&toggle_hud_and_cursor/1)
    :ok
  end

  def on_event({:ui_action, "__retry__"}, _context) do
    content = Core.Config.current()

    Helpers.with_scene_type(content.game_over_scene(), fn state ->
      Map.put(state, :retry, true)
    end)

    :ok
  end

  def on_event({:ui_action, "__quit__"}, context) do
    # 終了はコンテンツまたは上位層に委譲。イベントハンドラに通知するのみ。
    content = Core.Config.current()
    pid = content.event_handler(Map.get(context, :room_id, :main))
    if pid, do: send(pid, :quit_requested)
    :ok
  end

  def on_event(_event, _context), do: :ok

  defp toggle_hud_and_cursor(state) do
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
end
