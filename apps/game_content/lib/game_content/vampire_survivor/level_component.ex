defmodule GameContent.VampireSurvivor.LevelComponent do
  @moduledoc """
  レベル・EXP・アイテムドロップを担うコンポーネント。

  旧 `GameContent.VampireSurvivorRule` の `on_entity_removed/4` の責務を引き継ぐ。
  """
  @behaviour GameEngine.Component

  # ── アイテムドロップ確率（累積、1〜100 の乱数と比較）──────────────
  # Magnet: 2%、Potion: 5%（累積 7%）、Gem: 残り 93%
  @drop_magnet_threshold 2
  @drop_potion_threshold 7

  # ── アイテム種別 ID（EntityParams から取得）──────────────────────
  @item_gem    GameContent.EntityParams.item_kind_gem()
  @item_potion GameContent.EntityParams.item_kind_potion()
  @item_magnet GameContent.EntityParams.item_kind_magnet()

  # ── Potion の回復量 ────────────────────────────────────────────────
  @potion_heal_value 20

  @impl GameEngine.Component
  def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
    roll = :rand.uniform(100)
    cond do
      roll <= @drop_magnet_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)
      roll <= @drop_potion_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)
      true ->
        exp_reward = GameContent.EntityParams.enemy_exp_reward(kind_id)
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp_reward)
    end
    :ok
  end

  def on_event(_event, _context), do: :ok
end
