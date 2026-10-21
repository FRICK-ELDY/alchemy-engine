defmodule Contents.Components.Category.Device.Keyboard do
  @moduledoc """
  キーボード・UI アクションを扱うデバイスコンポーネント。

  ## 処理するイベント
  - `{:sprint, bool}` — 左 Shift キー押下状態
  - `{:key_pressed, :escape}` — HUD 表示トグル（グラブ中・解放中どちらでも届く）
  - `{:ui_action, "__retry__"}` — リトライ要求（game_over シーン state に retry: true を設定）

  ## UI アクション（ui_action_handlers で統一）
  Keyboard がデフォルトで `__retry__` を用意し、Content の `ui_action_handlers/0`
  とマージして適用する。Content が同じキーを返した場合は上書きされる（競合ではなく意図的なオーバーライド）。
  `__retry__` を Content に含めなくてもデフォルトで動作する。
  ハンドラ値: `{scene_type, fn state -> new_state end}`。
  例: `%{"__start__" => {:title, fn s -> Map.put(s, :start, true) end}}`

  ## 終了
  `"__quit__"` は既定ハンドラにしない。ノード停止は `Contents.Events.Game.stop_node_local/0`
  （ローカル呼び出し）だけが行う。コンテンツが `:quit` を返しても、ここではログして無視する。
  """
  @behaviour Core.Component

  require Logger

  alias Contents.Components.Category.Device.Helpers

  @impl Core.Component
  def on_event({:sprint, value}, context) when is_boolean(value) do
    with_room(context, fn room_id ->
      Helpers.with_playing_scene(room_id, fn state ->
        Map.put(state, :sprint, value)
      end)
    end)

    :ok
  end

  def on_event({:key_pressed, :escape}, context) do
    with_room(context, fn room_id ->
      Helpers.with_playing_scene(room_id, &toggle_hud_and_cursor/1)
    end)

    :ok
  end

  def on_event({:ui_action, action}, context) when is_binary(action) do
    content = Core.Config.current()
    handlers = get_effective_handlers(content)

    case Map.get(handlers, action) do
      {scene_type, fun} when is_function(fun, 1) ->
        with_room(context, fn room_id ->
          Helpers.with_scene_type(room_id, scene_type, fun)
        end)

        :ok

      :quit ->
        # 境界は Events.Game の許可リスト（`:quit` と `"__quit__"` は配送しない）。
        # ここは on_event/2 を Game 以外から直接呼んだときの保険。
        Logger.warning(
          "[Device.Keyboard] ignored :quit handler for #{inspect(action)} room=#{inspect(Map.get(context, :room_id))}"
        )

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

  # context に room_id が無いとき :main へは書かない。
  defp with_room(context, fun) do
    case Map.get(context, :room_id) do
      nil -> :ok
      room_id -> fun.(room_id)
    end
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
