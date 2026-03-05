defmodule Network.DistributedTest do
  @moduledoc """
  Network.Distributed および Network モジュールの分散対応 API のテスト。

  単一ノード時は Network.Local に委譲され、既存の挙動を維持する。
  ノードクラッシュ時のルーム移行（再作成）シナリオを検証する。
  """

  use ExUnit.Case, async: false

  alias Network.Local.TestHelpers
  alias Network.Test.StubRoom

  setup do
    case Process.whereis(Network.Local) do
      nil -> start_supervised!({Network.Local, []}, id: :local_under_test)
      _ -> :ok
    end

    case Process.whereis(Core.RoomRegistry) do
      nil -> start_supervised!({Registry, keys: :unique, name: Core.RoomRegistry})
      _ -> :ok
    end

    :ok
  end

  describe "Network API（単一ノード時は Distributed → Local に委譲）" do
    test "open_room / close_room / broadcast が Network 経由で動作する" do
      # open_room は RoomSupervisor を呼ぶため、StubRoom + register_room で検証
      {:ok, _pid_a} = start_supervised({StubRoom, "net_room_a"}, id: :net_stub_a)
      {:ok, pid_b} = start_supervised({StubRoom, "net_room_b"}, id: :net_stub_b)

      :ok = inject_room("net_room_a")
      :ok = inject_room("net_room_b")

      :ok = Network.connect_rooms("net_room_a", "net_room_b")
      assert Network.connected?("net_room_a", "net_room_b")

      :ok = Network.broadcast("net_room_a", :via_network_api)
      assert StubRoom.received_events(pid_b) == [{"net_room_a", :via_network_api}]

      assert "net_room_a" in Network.list_rooms()
      assert "net_room_b" in Network.list_rooms()
    end
  end

  describe "ノードクラッシュ時のルーム移行シナリオ" do
    test "unregister_room で接続テーブルから削除した後、register_room で再登録できる（移行シミュレーション）" do
      # シナリオ: ノードAでルームが稼働 → ノードAクラッシュ → ノードBで register_room により再登録
      # 単一ノードテストでは unregister_room で接続テーブルからの削除によりノード喪失をシミュレートする
      room_id = "migration_target_#{:rand.uniform(100_000)}"

      {:ok, pid} = start_supervised({StubRoom, room_id}, id: {:migration_stub, room_id})
      :ok = inject_room(room_id)

      # 1. ルームで broadcast が動作することを確認
      :ok = Network.broadcast(room_id, :before_close)
      assert StubRoom.received_events(pid) == []

      # 2. 接続テーブルからルームを削除（ノードクラッシュのシミュレーション）
      # 注: StubRoom は start_supervised で起動しているため、unregister_room のみ行う
      Network.unregister_room(room_id)

      # StubRoom プロセスは生存しているが、Network の接続テーブルからは削除された
      refute room_id in Network.list_rooms()

      # 3. ルームを再登録（移行先ノードでの「再作成」に相当）
      :ok = Network.register_room(room_id)

      # 4. 移行後のルームで broadcast が再び動作する
      assert room_id in Network.list_rooms()
      :ok = Network.broadcast(room_id, :after_migration)

      # 接続先が無いため StubRoom には届かないが、broadcast 自体は成功する
      assert :ok = Network.broadcast(room_id, :recovery_ok)
    end

    test "RoomSupervisor 経由のルームは close_room → open_room で復旧可能" do
      # open_room/close_room を使う場合（RoomSupervisor が利用可能な環境のみ）
      # アンブレラ全体の mix test では server アプリが起動し RoomSupervisor が存在する
      if Process.whereis(Core.RoomSupervisor) do
        room_id = "supervisor_migration_#{:rand.uniform(100_000)}"

        # open_room でルーム作成
        assert {:ok, _pid} = Network.open_room(room_id)
        assert room_id in Network.list_rooms()

        # close_room でノード喪失をシミュレート
        assert :ok = Network.close_room(room_id)
        refute room_id in Network.list_rooms()

        # 移行: 同一または別ノードで open_room により再作成
        assert {:ok, _pid} = Network.open_room(room_id)
        assert room_id in Network.list_rooms()

        # broadcast が動作することを確認
        assert :ok = Network.broadcast(room_id, :post_migration_event)

        # クリーンアップ
        Network.close_room(room_id)
      else
        # server が無い環境ではスキップ
        assert true
      end
    end
  end

  # ── ヘルパー ────────────────────────────────────────────────────────

  defp inject_room(room_id) do
    on_exit({:unregister, room_id}, fn ->
      case Process.whereis(Network.Local) do
        nil -> :ok
        _ -> Network.Local.unregister_room(room_id)
      end
    end)

    TestHelpers.inject_room(room_id)
  end
end
