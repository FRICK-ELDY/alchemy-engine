defmodule GameNetwork.ChannelTest do
  @moduledoc """
  GameNetwork.Channel の単体テスト。

  Phoenix.ChannelTest を使い、WebSocket 接続なしで
  チャンネルのメッセージハンドリングを検証する。
  """

  use ExUnit.Case, async: false

  # async: false の理由:
  # GameEngine.RoomRegistry は名前付きプロセス（モジュール名固定）のため、
  # 複数テストが並行して起動すると Registry の登録が衝突する。

  import Phoenix.ChannelTest

  @endpoint GameNetwork.Endpoint

  alias GameNetwork.Test.StubRoom

  setup do
    # このテストは GameNetwork.Application（または GameServer.Application）が
    # 起動した状態で実行される。
    # RoomRegistry / GameNetwork.Local / PubSub / Endpoint は既に起動済みのため、
    # ここでは何も起動しない。
    :ok
  end

  describe "join" do
    test "room:* トピックに join できる" do
      track("test_room")
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})

      assert {:ok, %{room_id: "test_room"}, _socket} =
               subscribe_and_join(socket, GameNetwork.Channel, "room:test_room")
    end

    test "不明なトピックは拒否される" do
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})

      assert {:error, %{reason: "unknown_topic"}} =
               subscribe_and_join(socket, GameNetwork.Channel, "unknown:topic")
    end
  end

  describe "ping / pong" do
    setup do
      track("ping_room")
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, GameNetwork.Channel, "room:ping_room")
      %{socket: socket}
    end

    test "ping を送ると pong が返る", %{socket: socket} do
      push(socket, "ping", %{})
      assert_push("pong", %{ts: ts})
      assert is_integer(ts)
    end
  end

  describe "input" do
    setup do
      test_pid = self()
      track("input_room")
      start_supervised!({StubRoom, {"input_room", notify: test_pid}}, id: :stub_input)
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, GameNetwork.Channel, "room:input_room")
      %{socket: socket}
    end

    test "input イベントが GameEvents プロセスに届く", %{socket: socket} do
      push(socket, "input", %{"dx" => 1.0, "dy" => 0.0})
      assert_receive {:move_input_received, 1.0, +0.0}, 200
    end

    test "存在しないルームへの input はエラーを返す" do
      track("ghost_room")
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, GameNetwork.Channel, "room:ghost_room")

      push(socket, "input", %{"dx" => 0.0, "dy" => 0.0})
      assert_push("error", %{reason: "room_not_found"})
    end
  end

  describe "action" do
    setup do
      test_pid = self()
      track("action_room")
      start_supervised!({StubRoom, {"action_room", notify: test_pid}}, id: :stub_action)
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, GameNetwork.Channel, "room:action_room")
      %{socket: socket}
    end

    test "action イベントが GameEvents プロセスに届く", %{socket: socket} do
      push(socket, "action", %{"name" => "__skip__"})
      assert_receive {:ui_action_received, "__skip__"}, 200
    end
  end

  describe "network_event" do
    test "GameEvents からの :network_event がクライアントに届く" do
      track("net_room")
      start_supervised!({StubRoom, "net_room"}, id: :stub_net)
      {:ok, socket} = connect(GameNetwork.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, GameNetwork.Channel, "room:net_room")

      send(socket.channel_pid, {:network_event, "other_room", :hello})

      # encode_event/1 はアトムを文字列に変換する（JSON 送信時の挙動と一致）
      assert_push("room_event", %{from: "other_room", data: "hello"})
    end
  end

  # ── テスト専用ヘルパー ──────────────────────────────────────────────

  # テスト終了時に register_room で登録した room_id を unregister_room でクリーンアップする。
  # on_exit のキーに {:unregister, room_id} を使うため、同一 room_id の重複登録は
  # ExUnit によって自動的に上書きされる（冪等）。
  defp track(room_id) do
    on_exit({:unregister, room_id}, fn ->
      case Process.whereis(GameNetwork.Local) do
        nil -> :ok
        _ -> GameNetwork.Local.unregister_room(room_id)
      end
    end)
  end
end
