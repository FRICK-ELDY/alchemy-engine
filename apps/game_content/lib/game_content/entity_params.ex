defmodule GameContent.EntityParams do
  @moduledoc """
  Rust の entity_params.rs / boss.rs と同じ値を Elixir 側でも保持するパラメータテーブル。

  フェーズ1〜4 の移行で Elixir 側がスコア・EXP・ボス HP を積算するために使用する。
  Rust 側の値と乖離しないよう、フェーズ0 の比較ログで定期的に検証すること。
  """

  # ── 敵 EXP 報酬（entity_params.rs の ENEMY_TABLE と同値）──────────
  # {kind_id => exp}
  @enemy_exp_rewards %{0 => 5, 1 => 3, 2 => 20, 3 => 10, 4 => 8}

  # ── ボス EXP 報酬（boss.rs の exp_reward と同値）──────────────────
  # {boss_kind_id => exp}
  @boss_exp_rewards %{0 => 200, 1 => 400, 2 => 800}

  # ── ボス最大 HP（boss.rs の max_hp と同値）────────────────────────
  # {boss_kind_id => max_hp}
  @boss_max_hp %{0 => 1000.0, 1 => 2000.0, 2 => 5000.0}

  # スコア = EXP × この係数（physics_step.rs の score 加算ロジックと同値）
  @score_per_exp 2

  @doc "敵種別 ID の EXP 報酬を返す"
  @spec enemy_exp_reward(non_neg_integer()) :: non_neg_integer()
  def enemy_exp_reward(kind_id), do: Map.fetch!(@enemy_exp_rewards, kind_id)

  @doc "ボス種別 ID の EXP 報酬を返す"
  @spec boss_exp_reward(non_neg_integer()) :: non_neg_integer()
  def boss_exp_reward(kind_id), do: Map.fetch!(@boss_exp_rewards, kind_id)

  @doc "ボス種別 ID の最大 HP を返す"
  @spec boss_max_hp(non_neg_integer()) :: float()
  def boss_max_hp(kind_id), do: Map.fetch!(@boss_max_hp, kind_id)

  @doc "EXP からスコア加算値を計算する（EXP × @score_per_exp）"
  @spec score_from_exp(non_neg_integer()) :: non_neg_integer()
  def score_from_exp(exp), do: exp * @score_per_exp
end
