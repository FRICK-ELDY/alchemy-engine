defmodule GameContent.EntityParamsTest do
  use ExUnit.Case, async: true

  alias GameContent.EntityParams

  describe "enemy_exp_reward/1" do
    test "全敵種別 ID (0..4) で正の整数を返す" do
      for kind_id <- 0..4 do
        reward = EntityParams.enemy_exp_reward(kind_id)
        assert is_integer(reward), "kind_id=#{kind_id} は整数を返すべき"
        assert reward > 0, "kind_id=#{kind_id} の EXP 報酬は正の整数であるべき"
      end
    end

    test "各種別の EXP 報酬が期待値と一致する" do
      # slime
      assert EntityParams.enemy_exp_reward(0) == 5
      # bat
      assert EntityParams.enemy_exp_reward(1) == 3
      # skeleton
      assert EntityParams.enemy_exp_reward(2) == 20
      # ghost
      assert EntityParams.enemy_exp_reward(3) == 10
      # golem
      assert EntityParams.enemy_exp_reward(4) == 8
    end

    test "未定義の kind_id は KeyError を発生させる" do
      assert_raise KeyError, fn -> EntityParams.enemy_exp_reward(99) end
    end
  end

  describe "boss_exp_reward/1" do
    test "全ボス種別 ID (0..2) で正の整数を返す" do
      for kind_id <- 0..2 do
        reward = EntityParams.boss_exp_reward(kind_id)
        assert is_integer(reward)
        assert reward > 0
      end
    end

    test "ボス EXP 報酬が期待値と一致する" do
      # slime_king
      assert EntityParams.boss_exp_reward(0) == 200
      # bat_lord
      assert EntityParams.boss_exp_reward(1) == 400
      # stone_golem
      assert EntityParams.boss_exp_reward(2) == 800
    end
  end

  describe "score_from_exp/1" do
    test "EXP → スコア変換が単調増加する" do
      exps = [0, 1, 5, 10, 50, 100, 1000]
      scores = Enum.map(exps, &EntityParams.score_from_exp/1)

      Enum.zip(scores, tl(scores))
      |> Enum.each(fn {a, b} ->
        assert a <= b, "スコアは EXP に対して単調増加すべき: #{a} <= #{b}"
      end)
    end

    test "スコアは EXP × 2 の線形関係" do
      for exp <- [0, 1, 5, 10, 100] do
        assert EntityParams.score_from_exp(exp) == exp * 2
      end
    end
  end

  describe "boss_max_hp/1" do
    test "全ボス種別 ID で正の float を返す" do
      for kind_id <- 0..2 do
        hp = EntityParams.boss_max_hp(kind_id)
        assert is_float(hp)
        assert hp > 0.0
      end
    end

    test "ボス最大 HP が期待値と一致する" do
      # slime_king
      assert EntityParams.boss_max_hp(0) == 1000.0
      # bat_lord
      assert EntityParams.boss_max_hp(1) == 2000.0
      # stone_golem
      assert EntityParams.boss_max_hp(2) == 5000.0
    end
  end
end
