defmodule Network.UDPTest do
  @moduledoc """
  `Network.UDP` および `Network.UDP.Protocol` の統合テスト。

  UDP ソケットを直接開いてパケットを送受信し、サーバーの動作を検証する。
  """

  use ExUnit.Case, async: false

  alias Network.UDP.Protocol

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
    # Network.UDP は Network.Application が起動済みであれば既に動いている。
    server_port = Network.UDP.port()
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
      frame_payload = <<0x08, 0x96, 0x01, 0x12, 0x03, "abc">>
      packet = {:frame, 6, frame_payload}
      assert {:ok, bin} = Protocol.encode(packet)
      assert {:ok, {:frame, 6, ^frame_payload}} = Protocol.decode(bin)
    end

    test ":frame は RenderFrame struct からもエンコードできる" do
      render_frame = %Alchemy.Render.RenderFrame{
        commands: [
          %Alchemy.Render.DrawCommand{
            kind:
              {:sprite_raw,
               %Alchemy.Render.SpriteRaw{
                 x: 10.0,
                 y: 20.0,
                 width: 30.0,
                 height: 40.0
               }}
          }
        ],
        camera: %Alchemy.Render.CameraParams{
          kind: {:camera_2d, %Alchemy.Render.Camera2d{offset_x: 1.0, offset_y: -2.0}}
        },
        ui: %Alchemy.Render.UiCanvas{
          nodes: [
            %Alchemy.Render.UiNode{
              rect: %Alchemy.Render.UiRect{
                anchor: "top_left",
                offset: [8.0, 16.0],
                size: {:fixed, %Alchemy.Render.UiSizeFixed{w: 120.0, h: 32.0}}
              },
              component: %Alchemy.Render.UiComponent{
                kind:
                  {:text,
                   %Alchemy.Render.UiText{text: "HP", color: [1.0, 1.0, 1.0, 1.0], size: 16.0}}
              },
              children: []
            }
          ]
        },
        mesh_definitions: []
      }

      assert {:ok, bin} = Protocol.encode({:frame, 6, render_frame})
      assert {:ok, {:frame, 6, frame_payload}} = Protocol.decode(bin)
      assert {:ok, decoded} = Protocol.decode_frame_payload_as_render_frame(frame_payload)

      assert %Alchemy.Render.CameraParams{
               kind: {:camera_2d, %Alchemy.Render.Camera2d{offset_x: 1.0, offset_y: -2.0}}
             } = decoded.camera

      assert [
               %Alchemy.Render.DrawCommand{
                 kind:
                   {:sprite_raw,
                    %Alchemy.Render.SpriteRaw{
                      x: 10.0,
                      y: 20.0,
                      width: 30.0,
                      height: 40.0
                    }}
               }
             ] = decoded.commands

      assert [
               %Alchemy.Render.UiNode{
                 rect: %Alchemy.Render.UiRect{
                   anchor: "top_left",
                   offset: [8.0, 16.0],
                   size: {:fixed, %Alchemy.Render.UiSizeFixed{w: 120.0, h: 32.0}}
                 },
                 component: %Alchemy.Render.UiComponent{
                   kind:
                     {:text,
                      %Alchemy.Render.UiText{text: "HP", color: [1.0, 1.0, 1.0, 1.0], size: 16.0}}
                 }
               }
             ] = decoded.ui.nodes
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

  describe "Protocol.compress_frame_payload / decompress_frame_payload" do
    test "frame payload を圧縮・展開できる" do
      frame_payload = :binary.copy(<<1, 2, 3, 4, 5>>, 100)
      assert {:ok, compressed} = Protocol.compress_frame_payload(frame_payload)
      assert {:ok, ^frame_payload} = Protocol.decompress_frame_payload(compressed)
    end

    test "空バイナリを圧縮・展開できる" do
      assert {:ok, compressed} = Protocol.compress_frame_payload(<<>>)
      assert {:ok, <<>>} = Protocol.decompress_frame_payload(compressed)
    end

    test "binary 以外は :invalid_frame_payload を返す" do
      assert {:error, :invalid_frame_payload} = Protocol.compress_frame_payload([:not, :binary])
    end

    test "不正なバイナリは :error を返す" do
      assert :error = Protocol.decompress_frame_payload(<<0xDE, 0xAD, 0xBE, 0xEF>>)
    end
  end

  # ── UDP サーバー統合テスト ───────────────────────────────────────────

  describe "JOIN / JOIN_ACK" do
    test "JOIN を送ると JOIN_ACK が返る", %{server_port: server_port} do
      room_id = "udp_join_#{System.unique_integer([:positive])}"
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      assert {:ok, {:join_ack, 1, ^room_id}} = recv_packet(sock)
    end

    test "JOIN 後にルームが Network.Local に登録される", %{server_port: server_port} do
      room_id = "udp_reg_#{System.unique_integer([:positive])}"
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      rooms = Network.Local.list_rooms()
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
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      # StubRoom を起動して RoomRegistry に登録する
      {:ok, stub_pid} =
        start_supervised(
          {Network.Test.StubRoom, {room_id, notify: self()}},
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
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      {:ok, _stub_pid} =
        start_supervised(
          {Network.Test.StubRoom, {room_id, notify: self()}},
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
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)
      port = client_port(sock)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      sessions = Network.UDP.sessions()

      assert Enum.any?(sessions, fn {{_ip, p}, session} ->
               p == port and session.room_id == room_id
             end)
    end

    test "LEAVE 後にセッションが削除される", %{server_port: server_port} do
      room_id = "udp_leave_#{System.unique_integer([:positive])}"
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

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

      sessions = Network.UDP.sessions()
      refute Enum.any?(sessions, fn {{_ip, p}, _} -> p == port end)
    end
  end

  describe "broadcast_frame/2" do
    test "broadcast_frame が JOIN 済みクライアントにフレームを届ける", %{server_port: server_port} do
      room_id = "udp_frame_#{System.unique_integer([:positive])}"
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      frame_payload = <<1, 2, 3, 4>>
      Network.UDP.broadcast_frame(room_id, frame_payload)

      assert {:ok, {:frame, _seq, ^frame_payload}} = recv_packet(sock, 1000)
    end

    test "broadcast_frame は RenderFrame struct でも送信できる", %{server_port: server_port} do
      room_id = "udp_frame_struct_#{System.unique_integer([:positive])}"
      on_exit(fn -> Network.Local.unregister_room(room_id) end)

      sock = open_client()
      on_exit(fn -> close_client(sock) end)

      :ok = send_packet(sock, server_port, Protocol.encode({:join, 1, room_id}))
      {:ok, {:join_ack, 1, _}} = recv_packet(sock)

      render_frame = %Alchemy.Render.RenderFrame{
        commands: [],
        camera: %Alchemy.Render.CameraParams{
          kind: {:camera_2d, %Alchemy.Render.Camera2d{offset_x: 0.25, offset_y: 0.5}}
        },
        ui: %Alchemy.Render.UiCanvas{nodes: []},
        mesh_definitions: []
      }

      Network.UDP.broadcast_frame(room_id, render_frame)

      assert {:ok, {:frame, _seq, frame_payload}} = recv_packet(sock, 1000)
      assert {:ok, decoded} = Protocol.decode_frame_payload_as_render_frame(frame_payload)
      assert %Alchemy.Render.RenderFrame{} = decoded
    end

    test "別ルームのクライアントにはフレームが届かない", %{server_port: server_port} do
      room_a = "udp_fa_#{System.unique_integer([:positive])}"
      room_b = "udp_fb_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        Network.Local.unregister_room(room_a)
        Network.Local.unregister_room(room_b)
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
      frame_payload = <<5, 6, 7>>
      Network.UDP.broadcast_frame(room_a, frame_payload)

      # sock_a は受信できる
      assert {:ok, {:frame, _seq, ^frame_payload}} = recv_packet(sock_a, 500)

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
