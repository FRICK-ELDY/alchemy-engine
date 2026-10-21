defmodule Contents.LocalUserComponentTest do
  use ExUnit.Case, async: false

  # :local_user_input ETS テーブルを共有するため async: false で並列実行を避ける。
  # アプリ起動で LocalUserComponent が on_ready 済みなら二重作成は発生しないが、
  # 他テストが同テーブルを使う場合は競合の可能性がある。

  alias Contents.LocalUserComponent

  @table :local_user_input
  @test_room_id :test_local_user_component

  # event_handler を渡して Core.RoomRegistry 参照を避ける（--no-start でテスト可能にする）
  defp test_context, do: %{room_id: @test_room_id, event_handler: self()}

  setup do
    LocalUserComponent.on_ready(make_ref())

    on_exit(fn ->
      # テスト用データをクリーンアップ（テーブルが存在する場合のみ）
      if :ets.whereis(@table) != :undefined do
        :ets.delete(@table, {@test_room_id, :move})
        :ets.delete(@table, {@test_room_id, :keys_held})
        :ets.delete(@table, {@test_room_id, :sprint})
      end
    end)

    :ok
  end

  describe "get_move_vector/1" do
    test "ETS にデータがないとき {0, 0} を返す" do
      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, 0}
    end

    test "ETS に move があるときその値を返す" do
      :ets.insert(@table, {{@test_room_id, :move}, {1, -1}})
      assert LocalUserComponent.get_move_vector(@test_room_id) == {1, -1}
    end
  end

  describe "on_event/2 — raw_key" do
    test "W キー押下で move_vector が上方向になる" do
      LocalUserComponent.on_event({:raw_key, :w, :pressed}, test_context())

      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, -1}
    end

    test "W キー離すと move_vector が {0, 0} になる" do
      LocalUserComponent.on_event({:raw_key, :w, :pressed}, test_context())
      LocalUserComponent.on_event({:raw_key, :w, :released}, test_context())

      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, 0}
    end

    test "WASD 同時押しで斜め方向になる" do
      LocalUserComponent.on_event({:raw_key, :w, :pressed}, test_context())
      LocalUserComponent.on_event({:raw_key, :d, :pressed}, test_context())

      assert LocalUserComponent.get_move_vector(@test_room_id) == {1, -1}
    end
  end

  describe "on_event/2 — move_input（ネットワーク経由）" do
    test "move_input で ETS に move が保存され get_move_vector で取得できる" do
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:move_input, 1.0, -0.5}, context)

      assert LocalUserComponent.get_move_vector(@test_room_id) == {1.0, -0.5}
    end

    test "整数の move_input も正規化されて float で保存される" do
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:move_input, 1, -1}, context)

      assert LocalUserComponent.get_move_vector(@test_room_id) == {1.0, -1.0}
    end
  end

  describe "on_event/2 — focus_lost" do
    test "focus_lost で move_vector が {0, 0} にリセットされる" do
      LocalUserComponent.on_event({:raw_key, :w, :pressed}, test_context())
      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, -1}

      LocalUserComponent.on_event(:focus_lost, test_context())
      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, 0}
    end
  end

  describe "on_event/2 — 未知イベント" do
    test "未知のイベントは :ok を返す" do
      context = %{room_id: @test_room_id}
      assert LocalUserComponent.on_event({:unknown_event}, context) == :ok
    end
  end
end
