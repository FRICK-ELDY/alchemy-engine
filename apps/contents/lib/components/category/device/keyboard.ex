defmodule Contents.Components.Category.Device.Keyboard do
  @moduledoc """
  キーボード・UI アクションを扱うデバイスコンポーネント。

  ## 処理するイベント
  - `{:sprint, bool}` — 左 Shift キー押下状態
  - `{:key_pressed, :escape}` — HUD 表示トグル（グラブ中・解放中どちらでも届く）
  - `{:ui_action, "__quit__"}` — 終了要求（実行は上位層に委譲。イベント送信のみ）
  - `{:ui_action, "__retry__"}` — リトライ要求（game_over シーン state に retry: true を設定）

  ## UI アクション（ui_action_handlers で統一）
  Keyboard がデフォルトで `__retry__` と `__quit__` を用意し、Content の `ui_action_handlers/0`
  とマージして適用する。Content が同じキーを返した場合は上書きされる（競合ではなく意図的なオーバーライド）。
  `__retry__` / `__quit__` を Content に含めなくてもデフォルトで動作する。
  ハンドラ値: `{scene_type, fn state -> new_state end}` または `:quit`。
  例: `%{"__start__" => {:title, fn s -> Map.put(s, :start, true) end}}`

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

  def on_event({:ui_action, action}, context) when is_binary(action) do
    content = Core.Config.current()
    handlers = get_effective_handlers(content)

    case Map.get(handlers, action) do
      {scene_type, fun} when is_function(fun, 1) ->
        Helpers.with_scene_type(scene_type, fun)
        :ok

      :quit ->
        pid = content.event_handler(Map.get(context, :room_id, :main))
        if pid, do: send(pid, :quit_requested)
        :ok

      nil ->
        # 未知のアクションは無視（FunctionClauseError を避ける）
        :ok
    end
  end

  def on_event(_event, _context), do: :ok

  # defaults を custom でマージ（custom 優先）。順序を誤ると __retry__ 等が上書きされない。
  defp get_effective_handlers(content) do
    defaults =
      %{}
      |> maybe_put_retry(content)
      |> Map.put("__quit__", :quit)

    custom =
      if function_exported?(content, :ui_action_handlers, 0) do
        content.ui_action_handlers()
      else
        %{}
      end

    Map.merge(defaults, custom)
  end

  # Content behaviour では game_over_scene/0 は必須コールバックのため、常に登録する。
  defp maybe_put_retry(acc, content) do
    Map.put(acc, "__retry__", {content.game_over_scene(), fn s -> Map.put(s, :retry, true) end})
  end

  defp toggle_hud_and_cursor(state) do
    if Map.get(state, :hud_visible, false) do
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
