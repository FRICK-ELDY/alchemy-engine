defmodule GameContent.VampireSurvivor.LevelComponent do
  @moduledoc """
  レベル・EXP・アイテムドロップ・武器選択 UI を担うコンポーネント。

  旧 `GameContent.VampireSurvivorRule` の `on_entity_removed/4` の責務を引き継ぐ。
  武器選択 UI アクション（`__skip__`・武器名）の処理もここで完結する。
  """
  @behaviour GameEngine.Component

  require Logger

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

  def on_event({:ui_action, "__skip__"}, context) do
    content = GameEngine.Config.current()
    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    if Map.get(playing_state, :level_up_pending, false) do
      Logger.info("[LEVEL UP] Skipped from renderer UI")
      GameEngine.SceneManager.update_by_module(content.playing_scene(), &content.apply_level_up_skipped/1)
      close_level_up_scene_if_active(content, context)
    end

    :ok
  end

  def on_event({:ui_action, weapon_name}, context) when is_binary(weapon_name) do
    content = GameEngine.Config.current()
    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    if Map.get(playing_state, :level_up_pending, false) do
      weapon_levels = Map.get(playing_state, :weapon_levels, %{})
      {action, weapon} = resolve_weapon(weapon_name, weapon_levels, content)

      case action do
        :apply ->
          Logger.info("[LEVEL UP] Weapon selected from renderer: #{inspect(weapon)}")
          GameEngine.SceneManager.update_by_module(content.playing_scene(), &content.apply_weapon_selected(&1, weapon))
        :skip ->
          GameEngine.SceneManager.update_by_module(content.playing_scene(), &content.apply_level_up_skipped/1)
      end

      close_level_up_scene_if_active(content, context)
    end

    :ok
  end

  def on_event({:ui_action, "__auto_pop__", scene_state}, context) do
    content = GameEngine.Config.current()

    case scene_state do
      %{choices: [first | _]} ->
        Logger.info("[LEVEL UP] Auto-selected: #{inspect(first)} -> resuming")
        GameEngine.SceneManager.update_by_module(content.playing_scene(), &content.apply_weapon_selected(&1, first))
      _ ->
        Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")
        GameEngine.SceneManager.update_by_module(content.playing_scene(), &content.apply_level_up_skipped/1)
    end

    _ = context
    :ok
  end

  def on_event(_event, _context), do: :ok

  # ── プライベート ──────────────────────────────────────────────────

  defp resolve_weapon(weapon_name, weapon_levels, content) do
    requested =
      try do
        String.to_existing_atom(weapon_name)
      rescue
        ArgumentError -> nil
      end

    weapons_registry = content.entity_registry().weapons
    allowed = weapons_registry |> Map.keys() |> MapSet.new()
    fallback = Map.keys(weapon_levels) |> List.first() || :magic_wand

    cond do
      is_atom(requested) and MapSet.member?(allowed, requested) ->
        {:apply, requested}

      MapSet.member?(allowed, fallback) ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available. Falling back to #{inspect(fallback)}.")
        {:apply, fallback}

      true ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available and no valid fallback. Skipping.")
        {:skip, :__skip__}
    end
  end

  defp close_level_up_scene_if_active(content, context) do
    if function_exported?(content, :level_up_scene, 0) do
      level_up_scene = content.level_up_scene()
      case GameEngine.SceneManager.current() do
        {:ok, %{module: ^level_up_scene}} ->
          context.pop_scene.()
        _ ->
          :ok
      end
    end
  end
end
