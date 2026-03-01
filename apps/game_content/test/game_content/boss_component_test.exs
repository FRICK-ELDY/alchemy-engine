defmodule GameContent.VampireSurvivor.BossComponentTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.BossComponent
  alias GameContent.VampireSurvivor.Scenes.Playing

  # BossComponent.on_frame_event は SceneManager.update_by_module を通じて
  # Playing シーンの state を更新する。
  # ここでは Playing シーンの state 更新関数を直接呼んで、
  # BossComponent が依存するロジックを検証する。

  describe "Playing.apply_boss_damaged/2（BossComponent.on_frame_event :boss_damaged のロジック）" do
    test "ダメージ分だけ boss_hp が減少する" do
      state = initial_playing_state(%{boss_hp: 1000.0, boss_max_hp: 1000.0, boss_kind_id: 0})
      new_state = Playing.apply_boss_damaged(state, 100.0)
      assert new_state.boss_hp == 900.0
    end

    test "boss_hp が 0 未満にならない" do
      state = initial_playing_state(%{boss_hp: 50.0, boss_max_hp: 1000.0, boss_kind_id: 0})
      new_state = Playing.apply_boss_damaged(state, 200.0)
      assert new_state.boss_hp == 0.0
    end

    test "boss_hp が nil のときは state を変更しない" do
      state = initial_playing_state(%{boss_hp: nil, boss_max_hp: nil, boss_kind_id: nil})
      new_state = Playing.apply_boss_damaged(state, 100.0)
      assert new_state.boss_hp == nil
    end
  end

  describe "Playing.apply_boss_spawn/2（BossComponent.on_frame_event :boss_spawn のロジック）" do
    test "boss_spawn で boss_hp が max_hp に設定される" do
      state = initial_playing_state(%{boss_hp: nil, boss_max_hp: nil, boss_kind_id: nil})
      boss_kind = GameContent.EntityParams.boss_kind_slime_king()
      expected_max_hp = GameContent.EntityParams.boss_max_hp(boss_kind)

      new_state = Playing.apply_boss_spawn(state, boss_kind)

      assert new_state.boss_hp == expected_max_hp
      assert new_state.boss_max_hp == expected_max_hp
      assert new_state.boss_kind_id == boss_kind
    end

    test "boss_spawn で boss_hp と boss_max_hp が同値になる" do
      state = initial_playing_state(%{boss_hp: nil, boss_max_hp: nil, boss_kind_id: nil})
      boss_kind = GameContent.EntityParams.boss_kind_slime_king()

      new_state = Playing.apply_boss_spawn(state, boss_kind)

      assert new_state.boss_hp == new_state.boss_max_hp
    end
  end

  describe "on_frame_event/2 — 未知イベント" do
    test "未知のイベントは :ok を返す" do
      context = %{world_ref: make_ref()}
      assert BossComponent.on_frame_event({:unknown_event, 1, 2, 3, 4}, context) == :ok
    end
  end

  describe "on_event/2 — 未知イベント" do
    test "未知のイベントは :ok を返す" do
      context = %{world_ref: make_ref()}
      assert BossComponent.on_event({:unknown_event}, context) == :ok
    end
  end

  # ── ヘルパー ──────────────────────────────────────────────────────

  defp initial_playing_state(overrides) do
    {:ok, base} = Playing.init(%{})
    Map.merge(base, overrides)
  end
end
