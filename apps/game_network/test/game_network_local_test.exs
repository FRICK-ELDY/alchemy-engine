defmodule GameNetwork.LocalTest do
  @moduledoc """
  GameNetwork.Local の単体テスト。

  RoomSupervisor / NIF には依存せず、StubRoom を使って
  接続管理・ブロードキャスト・OTP 隔離を検証する。
  """

  # async: false の理由:
  # GameEngine.RoomRegistry は名前付きプロセス（モジュール名固定）のため、
  # 複数テストが並行して起動すると Registry の登録が衝突する。
  use ExUnit.Case, async: false

  alias GameNetwork.Test.StubRoom
  alias GameNetwork.Local.TestHelpers

  setup do
    # このテストはアンブレラの mix test から実行される場合、
    # GameNetwork.Application（GameNetwork.Local を含む）が既に起動している。
    # GameNetwork.Local は名前付きプロセスのため、各テストで独立したインスタンスを
    # 起動することはできない。代わりに共有インスタンスをそのまま使い、
    # テスト間の独立性はユニークな room_id で確保する。
    case Process.whereis(GameNetwork.Local) do
      nil -> start_supervised!({GameNetwork.Local, []}, id: :local_under_test)
      _ -> :ok
    end

    case Process.whereis(GameEngine.RoomRegistry) do
      nil -> start_supervised!({Registry, keys: :unique, name: GameEngine.RoomRegistry})
      _ -> :ok
    end

    :ok
  end

  describe "ルーム管理" do
    test "register_room していないルームは list_rooms に現れない" do
      rooms = GameNetwork.Local.list_rooms()
      refute "never_registered_xyz" in rooms
    end

    test "connect_rooms は存在しないルームに対してエラーを返す" do
      assert {:error, {:room_not_found, "ghost"}} =
               GameNetwork.Local.connect_rooms("ghost", "also_ghost")
    end

    test "connected? は未接続のルームに false を返す" do
      refute GameNetwork.Local.connected?("a", "b")
    end

    test "disconnect_rooms は存在しないルームに対してゴーストエントリを作成しない" do
      :ok = GameNetwork.Local.disconnect_rooms("ghost_a", "ghost_b")
      refute "ghost_a" in GameNetwork.Local.list_rooms()
      refute "ghost_b" in GameNetwork.Local.list_rooms()
    end
  end

  describe "接続管理（StubRoom を使用）" do
    setup do
      {:ok, pid_a} = start_supervised({StubRoom, "room_a"}, id: :stub_a)
      {:ok, pid_b} = start_supervised({StubRoom, "room_b"}, id: :stub_b)

      %{pid_a: pid_a, pid_b: pid_b}
    end

    test "connect_rooms → broadcast でイベントが届く", %{pid_a: pid_a, pid_b: pid_b} do
      :ok = inject_room("room_a")
      :ok = inject_room("room_b")

      :ok = GameNetwork.Local.connect_rooms("room_a", "room_b")
      assert GameNetwork.Local.connected?("room_a", "room_b")
      assert GameNetwork.Local.connected?("room_b", "room_a")

      :ok = GameNetwork.Local.broadcast("room_a", :ping)

      # broadcast 内の deliver_event は send/2 で非同期にイベントを送信する。
      # received_events は GenServer.call であり、StubRoom のメッセージキューに
      # {:network_event, ...} より後に積まれる。
      # FIFO キューの性質上、received_events の call が処理される時点では
      # handle_info({:network_event, ...}) が必ず先に完了している。
      assert StubRoom.received_events(pid_b) == [{"room_a", :ping}]
      assert StubRoom.received_events(pid_a) == []
    end

    test "disconnect_rooms で接続が解除される" do
      :ok = inject_room("room_a")
      :ok = inject_room("room_b")

      :ok = GameNetwork.Local.connect_rooms("room_a", "room_b")
      assert GameNetwork.Local.connected?("room_a", "room_b")

      :ok = GameNetwork.Local.disconnect_rooms("room_a", "room_b")
      refute GameNetwork.Local.connected?("room_a", "room_b")
      refute GameNetwork.Local.connected?("room_b", "room_a")
    end

    test "broadcast は接続のないルームに対してエラーを返す" do
      assert {:error, :room_not_found} =
               GameNetwork.Local.broadcast("nonexistent", :event)
    end

    test "broadcast で接続先がない場合はイベントが届かない", %{pid_a: pid_a} do
      :ok = inject_room("room_a")

      :ok = GameNetwork.Local.broadcast("room_a", :ping)

      assert StubRoom.received_events(pid_a) == []
    end
  end

  describe "イベント受信の同期確認（notify オプション使用）" do
    test "broadcast で接続先には届き、送信元には届かない" do
      test_pid = self()

      start_supervised!({StubRoom, {"notify_a", notify: test_pid}}, id: :notify_a)
      start_supervised!({StubRoom, {"notify_b", notify: test_pid}}, id: :notify_b)

      :ok = inject_room("notify_a")
      :ok = inject_room("notify_b")
      :ok = GameNetwork.Local.connect_rooms("notify_a", "notify_b")

      :ok = GameNetwork.Local.broadcast("notify_a", :hello)

      # notify_b にはイベントが届く（同一 BEAM ノード内の send/2 はマイクロ秒オーダー）
      assert_receive {:stub_room_received, "notify_b", "notify_a", :hello}, 100
      # notify_a（送信元）にはイベントが届かない
      refute_receive {:stub_room_received, "notify_a", _, _}, 100
    end
  end

  describe "OTP 隔離" do
    test "一方のルームプロセスがクラッシュしても他方は継続する" do
      {:ok, pid_a} = start_supervised({StubRoom, "iso_a"}, id: :iso_a)
      {:ok, pid_b} = start_supervised({StubRoom, "iso_b"}, id: :iso_b)

      :ok = inject_room("iso_a")
      :ok = inject_room("iso_b")
      :ok = GameNetwork.Local.connect_rooms("iso_a", "iso_b")

      Process.exit(pid_a, :kill)

      # iso_b は生存している（OTP 隔離の証明）
      assert Process.alive?(pid_b)

      # iso_b への broadcast は room_not_found にならない（Local の接続テーブルは残る）
      # deliver_event は Registry lookup 失敗で warning を出すだけ
      assert :ok = GameNetwork.Local.broadcast("iso_b", :still_alive)
    end
  end

  describe "list_rooms" do
    test "register_room したルームが一覧に現れる" do
      :ok = inject_room("lr_a")
      :ok = inject_room("lr_b")

      rooms = GameNetwork.Local.list_rooms()
      assert "lr_a" in rooms
      assert "lr_b" in rooms
    end
  end

  # ── テスト専用ヘルパー ──────────────────────────────────────────────

  # GameNetwork.Local の接続テーブルにルームを登録し、on_exit でクリーンアップを登録する。
  # open_room は RoomSupervisor（NIF 起動）を呼ぶため、テストでは使わない。
  # on_exit のキーに {:unregister, room_id} を使うため、同一 room_id の重複登録は
  # ExUnit によって自動的に上書きされる（冪等）。
  defp inject_room(room_id) do
    on_exit({:unregister, room_id}, fn ->
      case Process.whereis(GameNetwork.Local) do
        nil -> :ok
        _ -> GameNetwork.Local.unregister_room(room_id)
      end
    end)

    TestHelpers.inject_room(room_id)
  end
end
