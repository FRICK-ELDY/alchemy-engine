defmodule Content.VampireSurvivor.SpawnComponent do
  @moduledoc """
  ワールド初期化・エンティティ登録を担うコンポーネント。

  旧 `Content.VampireSurvivorWorld` の責務を引き継ぐ。
  """
  @behaviour Core.Component

  @map_width 4096.0
  @map_height 4096.0

  @doc "アセットファイルのベースパスを返す"
  def assets_path, do: "vampire_survivor"

  @doc """
  エンティティ種別の ID マッピングを返す。

  エンジンは atom → u8 の変換にこのマッピングを使用する。
  """
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, golem: 2, skeleton: 3, ghost: 4},
      weapons: %{
        magic_wand: 0,
        axe: 1,
        cross: 2,
        whip: 3,
        fireball: 4,
        lightning: 5,
        garlic: 6
      },
      bosses: %{slime_king: 0, bat_lord: 1, stone_golem: 2}
    }
  end

  @doc "初期武器リストを返す"
  def initial_weapons, do: [:magic_wand]

  # R-E1: スコアポップアップの表示時間（秒）。add_score_popup NIF と RenderComponent の max_lifetime で使用。
  @doc "スコアポップアップの表示時間（秒）。Rust POPUP_LIFETIME の SSoT。"
  def score_popup_lifetime, do: 0.8

  @impl Core.Component
  def on_ready(world_ref) do
    Core.NifBridge.set_world_size(world_ref, @map_width, @map_height)

    Core.NifBridge.set_entity_params(
      world_ref,
      enemy_params(),
      weapon_params_impl(),
      Content.EntityParams.boss_params()
    )

    # I-2: 初期武器は Playing シーン state の weapon_levels から毎フレーム set_weapon_slots で注入する。
    # on_ready での add_weapon 呼び出しは不要。
    :ok
  end

  # ── エンティティパラメータ定義 ────────────────────────────────────
  # enemy_params / weapon_params の順序は Rust 側 decode_enemy_params /
  # decode_weapon_params と一致させること。
  # boss_params は Content.EntityParams.boss_params/0（SSoT）を参照。

  @doc """
  武器パラメータリスト。WeaponFormulas 等で SSoT として参照する。

  SpawnComponent 内部の on_ready では weapon_params_impl/0 を set_entity_params NIF に渡す。
  WeaponFormulas.weapon_upgrade_descs/3 がレベルアップカード表示に使用する。
  """
  def weapon_params, do: weapon_params_impl()

  defp enemy_params do
    [
      # 0: Slime
      %{
        max_hp: 30.0,
        speed: 80.0,
        radius: 20.0,
        damage_per_sec: 20.0,
        render_kind: 1,
        particle_color: [1.0, 0.5, 0.1, 1.0],
        passes_obstacles: false
      },
      # 1: Bat
      %{
        max_hp: 15.0,
        speed: 160.0,
        radius: 12.0,
        damage_per_sec: 10.0,
        render_kind: 2,
        particle_color: [0.7, 0.2, 0.9, 1.0],
        passes_obstacles: false
      },
      # 2: Golem
      %{
        max_hp: 150.0,
        speed: 40.0,
        radius: 32.0,
        damage_per_sec: 40.0,
        render_kind: 3,
        particle_color: [0.6, 0.6, 0.6, 1.0],
        passes_obstacles: false
      },
      # 3: Skeleton
      %{
        max_hp: 60.0,
        speed: 60.0,
        radius: 22.0,
        damage_per_sec: 15.0,
        render_kind: 5,
        particle_color: [0.9, 0.85, 0.7, 1.0],
        passes_obstacles: false
      },
      # 4: Ghost（壁すり抜け）
      %{
        max_hp: 40.0,
        speed: 100.0,
        radius: 16.0,
        damage_per_sec: 12.0,
        render_kind: 4,
        particle_color: [0.5, 0.5, 1.0, 0.8],
        passes_obstacles: true
      }
    ]
  end

  defp weapon_params_impl do
    [
      # fire_pattern: "aimed"=最近接扇状, "fixed_up"=上方向固定, "radial"=全方向,
      #               "whip"=扇形判定, "piercing"=貫通弾, "chain"=連鎖, "aura"=オーラ
      # range: Whip の基本半径 / Aura の基本半径
      # chain_count: Chain の基本連鎖数
      # 0: magic_wand
      %{
        cooldown: 1.0,
        damage: 10,
        as_u8: 0,
        bullet_table: [0, 1, 1, 2, 2, 3, 3, 4, 4],
        fire_pattern: "aimed",
        range: 0.0,
        chain_count: 0
      },
      # 1: axe
      %{
        cooldown: 1.5,
        damage: 25,
        as_u8: 1,
        bullet_table: nil,
        fire_pattern: "fixed_up",
        range: 0.0,
        chain_count: 0
      },
      # 2: cross
      %{
        cooldown: 2.0,
        damage: 15,
        as_u8: 2,
        bullet_table: [0, 4, 4, 4, 8, 8, 8, 8, 8],
        fire_pattern: "radial",
        range: 0.0,
        chain_count: 0
      },
      # 3: whip
      %{
        cooldown: 1.0,
        damage: 30,
        as_u8: 3,
        bullet_table: nil,
        fire_pattern: "whip",
        range: 120.0,
        chain_count: 0
      },
      # 4: fireball
      %{
        cooldown: 1.0,
        damage: 20,
        as_u8: 4,
        bullet_table: nil,
        fire_pattern: "piercing",
        range: 0.0,
        chain_count: 0
      },
      # 5: lightning
      %{
        cooldown: 1.0,
        damage: 15,
        as_u8: 5,
        bullet_table: nil,
        fire_pattern: "chain",
        range: 0.0,
        chain_count: 2
      },
      # 6: garlic
      %{
        cooldown: 0.2,
        damage: 1,
        as_u8: 6,
        bullet_table: nil,
        fire_pattern: "aura",
        range: 80.0,
        chain_count: 0
      }
    ]
  end
end
