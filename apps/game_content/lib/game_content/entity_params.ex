defmodule GameContent.EntityParams do
  @moduledoc """
  Rust の entity_params.rs / boss.rs と同じ値を Elixir 側でも保持するパラメータテーブル。

  フェーズ1〜4 の移行で Elixir 側がスコア・EXP・ボス HP を積算するために使用する。
  Rust 側の値と乖離しないよう、フェーズ0 の比較ログで定期的に検証すること。
  """

  # ── 敵種別 ID（entity_params.rs の ENEMY_TABLE インデックスと対応）──
  @enemy_slime 0
  @enemy_bat 1
  @enemy_skeleton 2
  @enemy_ghost 3
  @enemy_golem 4

  # ── 敵 EXP 報酬（entity_params.rs の ENEMY_TABLE と同値）──────────
  # {kind_id => exp}
  @enemy_exp_rewards %{
    @enemy_slime => 5,
    @enemy_bat => 3,
    @enemy_skeleton => 20,
    @enemy_ghost => 10,
    @enemy_golem => 8
  }

  # ── ボス種別 ID（boss.rs の kind_id と対応）──────────────────────
  @boss_slime_king 0
  @boss_bat_lord 1
  @boss_stone_golem 2

  # ── ボス EXP 報酬（boss.rs の exp_reward と同値）──────────────────
  # {boss_kind_id => exp}
  @boss_exp_rewards %{
    @boss_slime_king => 200,
    @boss_bat_lord => 400,
    @boss_stone_golem => 800
  }

  # ── ボス最大 HP（boss.rs の max_hp と同値）────────────────────────
  # {boss_kind_id => max_hp}
  @boss_max_hp %{
    @boss_slime_king => 1000.0,
    @boss_bat_lord => 2000.0,
    @boss_stone_golem => 5000.0
  }

  # ── ボスパラメータ（Phase 3-B: ボスAI制御用）──────────────────────
  # {boss_kind_id => %{speed, special_interval, ...}}
  @boss_params %{
    # Slime King: 直進してスライムをスポーン
    @boss_slime_king => %{
      speed: 60.0,
      special_interval: 5.0
    },
    # Bat Lord: 通常直進 + 特殊行動でダッシュ（無敵）
    @boss_bat_lord => %{
      speed: 200.0,
      special_interval: 4.0,
      # ダッシュ時の速度
      dash_speed: 500.0,
      # ダッシュ継続時間（ms）
      dash_duration_ms: 600
    },
    # Stone Golem: 低速直進 + 特殊行動で4方向に岩弾を発射
    @boss_stone_golem => %{
      speed: 30.0,
      special_interval: 6.0,
      # 岩弾の速度
      projectile_speed: 200.0,
      # 岩弾のダメージ
      projectile_damage: 50,
      # 岩弾の寿命（秒）
      projectile_lifetime: 3.0
    }
  }

  # スコア = EXP × この係数（physics_step.rs の score 加算ロジックと同値）
  @score_per_exp 2

  # ── アイテム種別 ID（Rust の ItemKind と対応）──────────────────────
  @item_gem 0
  @item_potion 1
  @item_magnet 2

  @doc "Gem のアイテム種別 ID を返す"
  @spec item_kind_gem() :: non_neg_integer()
  def item_kind_gem, do: @item_gem

  @doc "Potion のアイテム種別 ID を返す"
  @spec item_kind_potion() :: non_neg_integer()
  def item_kind_potion, do: @item_potion

  @doc "Magnet のアイテム種別 ID を返す"
  @spec item_kind_magnet() :: non_neg_integer()
  def item_kind_magnet, do: @item_magnet

  @doc "スライムの敵種別 ID を返す（SlimeKing の特殊行動スポーン等で使用）"
  @spec enemy_kind_slime() :: non_neg_integer()
  def enemy_kind_slime, do: @enemy_slime

  @doc "Slime King のボス種別 ID を返す"
  @spec boss_kind_slime_king() :: non_neg_integer()
  def boss_kind_slime_king, do: @boss_slime_king

  @doc "Bat Lord のボス種別 ID を返す"
  @spec boss_kind_bat_lord() :: non_neg_integer()
  def boss_kind_bat_lord, do: @boss_bat_lord

  @doc "Stone Golem のボス種別 ID を返す"
  @spec boss_kind_stone_golem() :: non_neg_integer()
  def boss_kind_stone_golem, do: @boss_stone_golem

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

  @doc "Phase 3-B: ボス種別 ID のパラメータ（speed, special_interval）を返す"
  @spec boss_params_by_id(non_neg_integer()) :: map()
  def boss_params_by_id(kind_id), do: Map.fetch!(@boss_params, kind_id)
end
