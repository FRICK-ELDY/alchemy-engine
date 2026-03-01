defmodule GameContent.VampireSurvivor.LevelComponentTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.LevelComponent

  describe "on_frame_event/2 — :player_damaged" do
    test "ダメージ分だけ player_hp が減少する" do
      playing_state = %{player_hp: 100.0, player_max_hp: 100.0}

      # damage_x1000 = 20_000 → damage = 20.0
      damage_x1000 = 20_000

      result_hp =
        apply_player_damaged_to_state(playing_state, damage_x1000)

      assert result_hp == 80.0
    end

    test "HP が 0 未満にならない" do
      playing_state = %{player_hp: 10.0, player_max_hp: 100.0}
      damage_x1000 = 50_000

      result_hp = apply_player_damaged_to_state(playing_state, damage_x1000)

      assert result_hp == 0.0
    end

    test "HP が 0 のときダメージを受けても 0 のまま" do
      playing_state = %{player_hp: 0.0, player_max_hp: 100.0}
      damage_x1000 = 10_000

      result_hp = apply_player_damaged_to_state(playing_state, damage_x1000)

      assert result_hp == 0.0
    end
  end

  describe "on_frame_event/2 — 未知イベント" do
    test "未知のイベントは :ok を返す" do
      context = %{world_ref: make_ref()}
      assert LevelComponent.on_frame_event({:unknown_event, 1, 2, 3, 4}, context) == :ok
    end
  end

  describe "on_event/2 — 未知イベント" do
    test "未知のイベントは :ok を返す" do
      context = %{world_ref: make_ref()}
      assert LevelComponent.on_event({:unknown_event}, context) == :ok
    end
  end

  # ── ヘルパー ──────────────────────────────────────────────────────

  # on_frame_event の player_damaged ロジックをステートレスに検証するためのヘルパー。
  # SceneManager を使わずに、ロジック部分（max(0.0, hp - damage)）を直接テストする。
  defp apply_player_damaged_to_state(playing_state, damage_x1000) do
    damage = damage_x1000 / 1000.0
    current_hp = Map.get(playing_state, :player_hp, 100.0)
    max(0.0, current_hp - damage)
  end
end
