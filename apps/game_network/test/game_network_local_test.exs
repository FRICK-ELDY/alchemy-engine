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
    # GameEngine.RoomRegistry を start_supervised で管理する。
    # テスト終了時に ExUnit が自動シャットダウンするため、
    # テスト間で Registry のプロセス自体が漏れない。
    # （Registry エントリは StubRoom プロセス終了時に自動削除される）
    start_supervised!({Registry, keys: :unique, name: GameEngine.RoomRegistry})

    # 各テストで独立した GameNetwork.Local インスタンスを起動する。
    start_supervised!({GameNetwork.Local, []}, id: :local_under_test)

    :ok
  end

  describe "ルーム管理" do
    test "open_room/close_room なしでは list_rooms が空を返す" do
      assert GameNetwork.Local.list_rooms() == []
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

      # broadcast は GenServer.call（同期）だが、deliver_event 内の send/2 は非同期。
      # received_events は GenServer.call のため、呼び出し時点で StubRoom の
      # メールボックスが順番に処理されており、handle_info の完了が保証される。
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

  # GameNetwork.Local の接続テーブルにルームを登録する。
  # open_room は RoomSupervisor（NIF 起動）を呼ぶため、テストでは使わない。
  defp inject_room(room_id) do
    TestHelpers.inject_room(room_id)
  end
end
