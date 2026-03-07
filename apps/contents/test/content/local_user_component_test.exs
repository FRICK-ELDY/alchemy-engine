defmodule Content.VampireSurvivor.LocalUserComponentTest do
  use ExUnit.Case, async: false

  # :local_user_input ETS テーブルを共有するため async: false で並列実行を避ける。
  # アプリ起動で LocalUserComponent が on_ready 済みなら二重作成は発生しないが、
  # 他テストが同テーブルを使う場合は競合の可能性がある。

  alias Content.VampireSurvivor.LocalUserComponent

  @table :local_user_input
  @test_room_id :test_local_user_component

  setup do
    LocalUserComponent.on_ready(make_ref())

    on_exit(fn ->
      # テスト用データをクリーンアップ
      :ets.delete(@table, {@test_room_id, :move})
      :ets.delete(@table, {@test_room_id, :keys_held})
      :ets.delete(@table, {@test_room_id, :sprint})
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
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:raw_key, :w, :pressed}, context)

      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, -1}
    end

    test "W キー離すと move_vector が {0, 0} になる" do
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:raw_key, :w, :pressed}, context)
      LocalUserComponent.on_event({:raw_key, :w, :released}, context)

      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, 0}
    end

    test "WASD 同時押しで斜め方向になる" do
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:raw_key, :w, :pressed}, context)
      LocalUserComponent.on_event({:raw_key, :d, :pressed}, context)

      assert LocalUserComponent.get_move_vector(@test_room_id) == {1, -1}
    end
  end

  describe "on_event/2 — focus_lost" do
    test "focus_lost で move_vector が {0, 0} にリセットされる" do
      context = %{room_id: @test_room_id}

      LocalUserComponent.on_event({:raw_key, :w, :pressed}, context)
      assert LocalUserComponent.get_move_vector(@test_room_id) == {0, -1}

      LocalUserComponent.on_event(:focus_lost, context)
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
