defmodule GameNetwork.Channel do
  @moduledoc """
  Phoenix Channel によるリアルタイム WebSocket トランスポート。

  クライアント（ブラウザ等）は `"room:<room_id>"` トピックに join することで
  ゲームルームに参加できる。

  ## メッセージフロー

  ### クライアント → サーバー

  | イベント           | ペイロード例                        | 説明                         |
  |:-------------------|:------------------------------------|:-----------------------------|
  | `"input"`          | `%{"dx" => 0.5, "dy" => -1.0}`      | 移動入力（dx/dy は省略可、省略時は 0.0）|
  | `"action"`         | `%{"name" => "select_weapon", ...}` | UI アクション                |
  | `"ping"`           | `%{}`                               | 疎通確認                     |

  ### サーバー → クライアント

  | イベント           | ペイロード例                              | 説明                         |
  |:-------------------|:------------------------------------------|:-----------------------------|
  | `"frame"`          | `%{"events" => [...]}`                    | フレームイベント配信         |
  | `"room_event"`     | `%{"from" => "room_b", "data" => "hello"}`| ルーム間ブロードキャスト     |
  | `"pong"`           | `%{"ts" => 1234567890}`                   | ping への応答                |
  | `"error"`          | `%{"reason" => "room_not_found"}`         | エラー通知                   |

  ## エンコードポリシー

  サーバーからクライアントへ送信するデータは `encode_event/1` で変換される。
  - タプルはリストに展開される: `{:hit, 10}` → `["hit", 10]`
  - アトムは文字列に変換される: `:hello` → `"hello"`
  - その他の値はそのまま送信される

  これは JSON シリアライズ時の挙動（アトム → 文字列）と一致させるためである。
  `assert_push` はチャンネルプロセス内の値を検査するため、
  テストでは文字列 `"hello"` を期待すること。

  ## 使い方（JavaScript クライアント側）

      import { Socket } from "phoenix"
      const socket = new Socket("/socket", {})
      socket.connect()
      const channel = socket.channel("room:my_room", {})
      channel.join()
        .receive("ok", () => console.log("joined"))
        .receive("error", ({reason}) => console.error(reason))
      channel.push("input", {dx: 0.5, dy: 0.0})
      channel.on("frame", payload => render(payload))
  """

  use Phoenix.Channel
  require Logger

  # ── join ────────────────────────────────────────────────────────────

  @impl true
  def join("room:" <> room_id, _params, socket) do
    case GameNetwork.Local.register_room(room_id) do
      :ok ->
        Logger.info("[GameNetwork.Channel] Client joined room=#{room_id}")
        socket = assign(socket, :room_id, room_id)
        {:ok, %{room_id: room_id}, socket}

      {:error, reason} ->
        Logger.warning("[GameNetwork.Channel] Failed to register room=#{room_id}: #{inspect(reason)}")
        {:error, %{reason: "register_failed", detail: inspect(reason)}}
    end
  end

  def join(topic, _params, _socket) do
    Logger.warning("[GameNetwork.Channel] Rejected join for unknown topic=#{topic}")
    {:error, %{reason: "unknown_topic"}}
  end

  # ── クライアント → サーバー ──────────────────────────────────────────

  @impl true
  def handle_in("input", payload, socket) do
    room_id = socket.assigns.room_id
    dx = payload |> Map.get("dx", 0) |> to_float()
    dy = payload |> Map.get("dy", 0) |> to_float()

    case GameEngine.RoomRegistry.get_loop(room_id) do
      {:ok, pid} ->
        send(pid, {:move_input, dx, dy})

      :error ->
        push(socket, "error", %{reason: "room_not_found"})
    end

    {:noreply, socket}
  end

  def handle_in("action", %{"name" => name}, socket) do
    room_id = socket.assigns.room_id

    case GameEngine.RoomRegistry.get_loop(room_id) do
      {:ok, pid} ->
        send(pid, {:ui_action, name})

      :error ->
        push(socket, "error", %{reason: "room_not_found"})
    end

    {:noreply, socket}
  end

  def handle_in("action", _payload, socket) do
    push(socket, "error", %{reason: "missing_field", detail: "name"})
    {:noreply, socket}
  end

  def handle_in("ping", _payload, socket) do
    push(socket, "pong", %{ts: System.system_time(:millisecond)})
    {:noreply, socket}
  end

  def handle_in(event, _payload, socket) do
    Logger.debug("[GameNetwork.Channel] Unknown event=#{event} room=#{socket.assigns.room_id}")
    {:noreply, socket}
  end

  # ── サーバー → クライアント（GameEvents からの push）────────────────

  @impl true
  def handle_info({:network_event, from_room, event}, socket) do
    push(socket, "room_event", %{from: to_string(from_room), data: encode_event(event)})
    {:noreply, socket}
  end

  # GameEngine.GameEvents は {:frame_events, events} の2要素タプルを送信する。
  # tick は GameEvents 側に存在しないため、ペイロードには含めない。
  def handle_info({:frame_events, events}, socket) do
    push(socket, "frame", %{events: Enum.map(events, &encode_event/1)})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── プライベート ─────────────────────────────────────────────────────

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(_), do: 0.0

  # イベントを JSON シリアライズ可能な形式に変換する。
  # アトムは文字列に統一する（JSON 送信時の挙動と一致させるため）。
  defp encode_event(event) when is_tuple(event) do
    event |> Tuple.to_list() |> Enum.map(&encode_value/1)
  end

  defp encode_event(event), do: encode_value(event)

  defp encode_value(v) when is_atom(v), do: to_string(v)
  defp encode_value(v), do: v
end
