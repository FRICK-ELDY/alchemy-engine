defmodule GameNetwork.UDPTest do
  @moduledoc """
  `GameNetwork.UDP` および `GameNetwork.UDP.Protocol` の統合テスト。

  UDP ソケットを直接開いてパケットを送受信し、サーバーの動作を検証する。
  """

  use ExUnit.Case, async: false

  alias GameNetwork.UDP.Protocol

  # テスト用 UDP クライアントを起動するヘルパー
  defp open_client do
    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    sock
  end

  defp close_client(sock), do: :gen_udp.close(sock)

  defp client_port(sock) do
    {:ok, port} = :inet.port(sock)
    port
  end

  # Protocol.encode/1 は {:ok, binary()} を返すため、ここで unwrap する。
  defp send_packet(sock, server_port, {:ok, packet}) do
    :gen_udp.send(sock, {127, 0, 0, 1}, server_port, packet)
  end

  defp recv_packet(sock, timeout \\ 500) do
    case :gen_udp.recv(sock, 0, timeout) do
      {:ok, {_ip, _port, data}} -> Protocol.decode(data)
      {:error, reason} -> {:error, reason}
    end
  end

  # ── セットアップ ─────────────────────────────────────────────────────

  setup do
    # GameNetwork.UDP は GameNetwork.Application が起動済みであれば既に動いている。
    server_port = GameNetwork.UDP.port()
    {:ok, server_port: server_port}
  end

  # ── Protocol 単体テスト ─────────────────────────────────────────────

  describe "Protocol.encode/decode" do
    test ":join パケットをエンコード・デコードできる" do
      packet = {:join, 1, "room_a"}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":join_ack パケットをエンコード・デコードできる" do
      packet = {:join_ack, 2, "room_b"}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":leave パケットをエンコード・デコードできる" do
      packet = {:leave, 3, "room_c"}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":input パケットをエンコード・デコードできる" do
      packet = {:input, 4, 1.5, -0.5}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":action パケットをエンコード・デコードできる" do
      packet = {:action, 5, "jump"}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":frame パケットをエンコード・デコードできる" do
      events = [{:player_moved, 1.0, 2.0}, {:score_updated, 100}]
      packet = {:frame, 6, events}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, {:frame, 6, ^events}} = Protocol.decode(bin)
    end

    test ":ping パケットをエンコード・デコードできる" do
      packet = {:ping, 7}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":pong パケットをエンコード・デコードできる" do
      packet = {:pong, 8, 1_700_000_000_000}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test ":error パケットをエンコード・デコードできる" do
      packet = {:error, 9, "room_not_found"}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, ^packet} = Protocol.decode(bin)
    end

    test "不正なバイナリは :invalid_packet を返す" do
      assert {:error, :invalid_packet} = Protocol.decode(<<0xFF, 0x00>>)
    end

    test "空バイナリは :invalid_packet を返す" do
      assert {:error, :invalid_packet} = Protocol.decode(<<>>)
    end
  end

  describe "Protocol.compress_events / decompress_events" do
    test "イベントリストを圧縮・展開できる" do
      events = Enum.map(1..50, fn i -> {:event, i, i * 1.0} end)
      assert {:ok, compressed} = Protocol.compress_events(events)
      assert {:ok, ^events} = Protocol.decompress_events(compressed)
    end

    test "空リストを圧縮・展開できる" do
      assert {:ok, compressed} = Protocol.compress_events([])
      assert {:ok, []} = Protocol.decompress_events(compressed)
    end

    test "不正なバイナリは :error を返す" do
      assert :error = Protocol.decompress_events(<<0xDE, 0xAD, 0xBE, 0xEF>>)
    end
  end

  # ── UDP サーバー統合テスト ───────────────────────────────────────────

  describe "JOIN / JOIN_ACK" do
    test "JOIN を送ると JOIN_ACK が返る", %{server_port: server_port} do
      room_id = "udp_join_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      assert {:ok, {:join_ack, 1, ^room_id}} = recv_packet(sock)
    end

    test "JOIN 後にルームが GameNetwork.Local に登録される", %{server_port: server_port} do
      room_id = "udp_reg_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      rooms = GameNetwork.Local.list_rooms()
      assert room_id in rooms
    end
  end

  describe "PING / PONG" do
    test "PING を送ると PONG が返る", %{server_port: server_port} do
      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:ping, 42}))
      assert {:ok, {:pong, 42, ts}} = recv_packet(sock)
      assert is_integer(ts)
      assert ts > 0
    end
  end

  describe "INPUT 転送" do
    test "JOIN 後の INPUT が GameEvents に届く", %{server_port: server_port} do
      room_id = "udp_input_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      # StubRoom を起動して RoomRegistry に登録する
      {:ok, stub_pid} =
        start_supervised(
          {GameNetwork.Test.StubRoom, {room_id, notify: self()}},
          id: :"stub_#{room_id}"
        )

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      # JOIN
      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      # INPUT 送信
      :ok = send_packet(sock, server_port, Protocol.encode({:input, 2, 1.0, -1.0}))

      # StubRoom が :move_input を受け取ったことを確認
      assert_receive {:move_input_received, 1.0, -1.0}, 500

      # stub_pid が生きていることを確認（クラッシュしていない）
      assert Process.alive?(stub_pid)
    end
  end

  describe "ACTION 転送" do
    test "JOIN 後の ACTION が GameEvents に届く", %{server_port: server_port} do
      room_id = "udp_action_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      {:ok, _stub_pid} =
        start_supervised(
          {GameNetwork.Test.StubRoom, {room_id, notify: self()}},
          id: :"stub_#{room_id}"
        )

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      :ok = send_packet(sock, server_port, Protocol.encode({:action, 3, "jump"}))

      assert_receive {:ui_action_received, "jump"}, 500
    end
  end

  describe "セッション管理" do
    test "sessions/0 が接続中クライアントを返す", %{server_port: server_port} do
      room_id = "udp_sess_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)
      port = client_port(sock)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      sessions = GameNetwork.UDP.sessions()

      assert Enum.any?(sessions, fn {{_ip, p}, session} ->
               p == port and session.room_id == room_id
             end)
    end

    test "LEAVE 後にセッションが削除される", %{server_port: server_port} do
      room_id = "udp_leave_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)
      port = client_port(sock)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      :ok = send_packet(sock, server_port, Protocol.encode({:leave, 2, room_id}))

      # LEAVE パケットの処理は UDP 受信 → handle_info の順に非同期で進む。
      # sessions/0 は GenServer.call であり、LEAVE の handle_info より後に
      # メッセージキューに積まれるため、呼び出し時点で LEAVE の処理完了が保証される。
      # ただし UDP パケットが OS のネットワークスタックを経由するため、
      # handle_info に届くまでの時間は保証されない。
      # PING/PONG で同期ポイントを作り、その後に sessions/0 を呼ぶことで
      # LEAVE の処理完了を確実に待機する。
      :ok = send_packet(sock, server_port, Protocol.encode({:ping, 999}))
      {:ok, {:pong, 999, _}} = recv_packet(sock, 500)

      sessions = GameNetwork.UDP.sessions()
      refute Enum.any?(sessions, fn {{_ip, p}, _} -> p == port end)
    end
  end

  describe "broadcast_frame/2" do
    test "broadcast_frame が JOIN 済みクライアントにフレームを届ける", %{server_port: server_port} do
      room_id = "udp_frame_#{System.unique_integer([:positive])}"
      on_exit(fn -> GameNetwork.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      events = [:event_a, :event_b]
      GameNetwork.UDP.broadcast_frame(room_id, events)

      assert {:ok, {:frame, _seq, ^events}} = recv_packet(sock, 1000)
    end

    test "別ルームのクライアントにはフレームが届かない", %{server_port: server_port} do
      room_a = "udp_fa_#{System.unique_integer([:positive])}"
      room_b = "udp_fb_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        GameNetwork.Local.unregister_room(room_a)
        GameNetwork.Local.unregister_room(room_b)
      end)

      sock_a = open_client()
      sock_b = open_client()

      on_exit(fn ->
        close_client(sock_a)
        close_client(sock_b)
      end)

      :ok = send_packet(sock_a, server_port, Protocol.encode({:join, 1, room_a}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock_a)

      :ok = send_packet(sock_b, server_port, Protocol.encode({:join, 2, room_b}))
      {:ok, {:join_ack, 2, _}} = recv_packet(sock_b)

      # room_a にのみブロードキャスト
      GameNetwork.UDP.broadcast_frame(room_a, [:only_for_a])

      # sock_a は受信できる
      assert {:ok, {:frame, _seq, [:only_for_a]}} = recv_packet(sock_a, 500)

      # sock_b は受信しない
      assert {:error, :timeout} = recv_packet(sock_b, 200)
    end
  end

  describe "不正パケット耐性" do
    test "不正なバイナリを送ってもサーバーがクラッシュしない", %{server_port: server_port} do
      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = :gen_udp.send(sock, {127, 0, 0, 1}, server_port, <<0xFF, 0x00, 0x01, 0x02>>)

      # サーバーが生きていることを PING で確認
      :ok = send_packet(sock, server_port, Protocol.encode({:ping, 99}))
      assert {:ok, {:pong, 99, _ts}} = recv_packet(sock, 500)
    end
  end
end
