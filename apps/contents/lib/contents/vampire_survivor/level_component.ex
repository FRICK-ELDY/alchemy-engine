defmodule Content.VampireSurvivor.LevelComponent do
  @moduledoc """
  レベル・EXP・スコア・プレイヤー HP・アイテムドロップ・武器選択 UI を担うコンポーネント。

  ## on_frame_event
  Rust フレームイベントを受け取り、Playing シーン state を更新する。
  - `{:enemy_killed, ...}` — EXP 加算・スコア更新・アイテムドロップ
  - `{:player_damaged, ...}` — プレイヤー HP 減算

  ## on_nif_sync
  毎フレーム、Playing シーン state の差分を NIF に注入する。
  ダーティフラグはプロセス辞書で管理する。
  """
  @behaviour Core.Component

  require Logger

  @drop_magnet_threshold 2
  @drop_potion_threshold 7

  @item_gem Content.EntityParams.item_kind_gem()
  @item_potion Content.EntityParams.item_kind_potion()
  @item_magnet Content.EntityParams.item_kind_magnet()

  @potion_heal_value 20
  @invincible_ms 500

  # ── on_frame_event: Rust フレームイベント処理 ──────────────────────

  @impl Core.Component
  def on_frame_event({:enemy_killed, enemy_kind, x_bits, y_bits, _}, context) do
    content = Core.Config.current()
    exp = content.enemy_exp_reward(enemy_kind)
    x = bits_to_f32(x_bits)
    y = bits_to_f32(y_bits)

    score_delta = apply_kill_to_scene(content, exp)

    call_nif(:add_score_popup, fn ->
      Core.NifBridge.add_score_popup(context.world_ref, x, y, score_delta)
    end)

    spawn_item_drop(context.world_ref, enemy_kind, x, y, exp)

    :ok
  end

  def on_frame_event({:player_damaged, damage_x1000, _, _, _}, context) do
    damage = damage_x1000 / 1000.0
    content = Core.Config.current()
    runner = content.flow_runner(:main)
    invincible_until_ms = context.now + @invincible_ms

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        content.playing_scene(),
        &apply_player_damage(&1, damage, invincible_until_ms)
      )
    end

    :ok
  end

  def on_frame_event({:item_pickup, item_kind, value, _, _}, _context)
      when item_kind == @item_potion do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      heal = value

      Contents.SceneStack.update_by_module(runner, content.playing_scene(), fn state ->
        max_hp = Map.get(state, :player_max_hp, 100.0)
        current_hp = Map.get(state, :player_hp, 100.0)
        new_hp = min(max_hp, current_hp + heal)
        Map.put(state, :player_hp, new_hp)
      end)
    end

    :ok
  end

  def on_frame_event({:item_pickup, _item_kind, _value, _, _}, _context), do: :ok

  # 同一フレームでスロット数分のイベントが順次 dispatch される。
  # update_by_module は同期的に実行されるため、各 Map.put は競合せずマージされる。
  def on_frame_event({:weapon_cooldown_updated, kind_id, cooldown_bits, _, _}, _context) do
    cooldown = bits_to_f32(cooldown_bits)
    content = Core.Config.current()
    runner = content.flow_runner(:main)
    weapon_name = kind_id_to_weapon_name(kind_id, content)

    if runner && weapon_name do
      Contents.SceneStack.update_by_module(runner, content.playing_scene(), fn state ->
        cooldowns = Map.get(state, :weapon_cooldowns, %{})
        Map.put(state, :weapon_cooldowns, Map.put(cooldowns, weapon_name, cooldown))
      end)
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  defp apply_player_damage(state, damage, invincible_until_ms) do
    state
    |> Map.update(:player_hp, 100.0, fn hp -> max(0.0, hp - damage) end)
    |> Map.put(:invincible_until_ms, invincible_until_ms)
  end

  # ── on_nif_sync: 毎フレーム NIF 注入 ─────────────────────────────

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    sync_player_snapshot(context.world_ref, playing_state, context)
    sync_elapsed(context.world_ref, playing_state, context)
    sync_weapon_slots(context.world_ref, content, playing_state)

    :ok
  end

  # ── on_event: UI アクション・エンジン内部イベント ─────────────────

  @impl Core.Component
  def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
    roll = :rand.uniform(100)

    cond do
      roll <= @drop_magnet_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)

      roll <= @drop_potion_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)

      true ->
        exp_reward = Content.EntityParams.enemy_exp_reward(kind_id)
        Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp_reward)
    end

    :ok
  end

  def on_event({:ui_action, "__skip__"}, context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    if Map.get(playing_state, :level_up_pending, false) and runner do
      Logger.info("[LEVEL UP] Skipped from renderer UI")

      Contents.SceneStack.update_by_module(
        runner,
        content.playing_scene(),
        &content.apply_level_up_skipped/1
      )

      close_level_up_scene_if_active(content, context, runner)
    end

    :ok
  end

  def on_event({:ui_action, weapon_name}, context) when is_binary(weapon_name) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    if Map.get(playing_state, :level_up_pending, false) and runner do
      weapon_levels = Map.get(playing_state, :weapon_levels, %{})
      {action, weapon} = resolve_weapon(weapon_name, weapon_levels, content)

      case action do
        :apply ->
          Logger.info("[LEVEL UP] Weapon selected from renderer: #{inspect(weapon)}")

          Contents.SceneStack.update_by_module(
            runner,
            content.playing_scene(),
            &content.apply_weapon_selected(&1, weapon)
          )

        :skip ->
          Contents.SceneStack.update_by_module(
            runner,
            content.playing_scene(),
            &content.apply_level_up_skipped/1
          )
      end

      close_level_up_scene_if_active(content, context, runner)
    end

    :ok
  end

  def on_event({:ui_action, "__auto_pop__", scene_state}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      case scene_state do
        %{choices: [first | _]} ->
          Logger.info("[LEVEL UP] Auto-selected: #{inspect(first)} -> resuming")

          Contents.SceneStack.update_by_module(
            runner,
            content.playing_scene(),
            &content.apply_weapon_selected(&1, first)
          )

        _ ->
          Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")

          Contents.SceneStack.update_by_module(
            runner,
            content.playing_scene(),
            &content.apply_level_up_skipped/1
          )
      end
    end

    :ok
  end

  def on_event(_event, _context), do: :ok

  # ── プライベート: NIF 同期 ────────────────────────────────────────

  defp sync_player_snapshot(world_ref, playing_state, context) do
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    invincible_until_ms = Map.get(playing_state, :invincible_until_ms)
    now_ms = context.now

    invincible_timer =
      case invincible_until_ms do
        nil -> 0.0
        until when until > now_ms -> (until - now_ms) / 1000.0
        _ -> 0.0
      end

    prev = Process.get({__MODULE__, :last_player_snapshot})

    if {player_hp, invincible_timer} != prev do
      call_nif(:set_player_snapshot, fn ->
        Core.NifBridge.set_player_snapshot(world_ref, player_hp, invincible_timer)
      end)

      Process.put({__MODULE__, :last_player_snapshot}, {player_hp, invincible_timer})
    end
  end

  defp sync_elapsed(world_ref, playing_state, context) do
    elapsed_ms =
      case Map.get(playing_state, :elapsed_ms) do
        nil -> context.elapsed
        val -> val
      end

    prev = Process.get({__MODULE__, :last_elapsed_ms})

    if elapsed_ms != prev do
      call_nif(:set_elapsed_seconds, fn ->
        Core.NifBridge.set_elapsed_seconds(world_ref, elapsed_ms / 1000.0)
      end)

      Process.put({__MODULE__, :last_elapsed_ms}, elapsed_ms)
    end
  end

  defp sync_weapon_slots(world_ref, content, playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels)
    weapon_cooldowns = Map.get(playing_state, :weapon_cooldowns, %{})
    playing_scene = content.playing_scene()

    slots =
      cond do
        weapon_levels == nil ->
          nil

        function_exported?(playing_scene, :weapon_slots_for_nif, 2) ->
          playing_scene.weapon_slots_for_nif(weapon_levels, weapon_cooldowns)

        function_exported?(playing_scene, :weapon_slots_for_nif, 1) ->
          # R-W2: 4 要素 (kind_id, level, cooldown, precomputed_damage) が必要。
          # 1 引数版では precomputed_damage を計算できないため 0 を渡す（全武器ダメージ 0 になる）。
          # 新規 contents では weapon_slots_for_nif/2 を実装すること。
          playing_scene.weapon_slots_for_nif(weapon_levels)
          |> Enum.map(fn {k, l} -> {k, l, 0.0, 0} end)

        true ->
          nil
      end

    if slots do
      call_nif(:set_weapon_slots, fn ->
        Core.NifBridge.set_weapon_slots(world_ref, slots)
      end)
    end
  end

  defp kind_id_to_weapon_name(kind_id, content) do
    registry = content.entity_registry().weapons

    registry
    |> Enum.find_value(fn {name, id} -> if id == kind_id, do: name end)
  end

  # ── プライベート: フレームイベント処理ヘルパー ────────────────────

  defp apply_kill_to_scene(content, exp) do
    score_delta = content.score_from_exp(exp)
    runner = content.flow_runner(:main)

    # シーンが見つからない場合（Playing シーン以外での敵撃破等）は
    # update_by_module が何もしないため、score_delta のみ返して NIF ポップアップに使う
    if runner do
      Contents.SceneStack.update_by_module(runner, content.playing_scene(), fn state ->
        state
        |> Map.update(:score, score_delta, &(&1 + score_delta))
        |> Map.update(:kill_count, 1, &(&1 + 1))
        |> content.playing_scene().accumulate_exp(exp)
      end)
    end

    score_delta
  end

  defp spawn_item_drop(world_ref, _enemy_kind, x, y, exp) do
    roll = :rand.uniform(100)

    cond do
      roll <= @drop_magnet_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)

      roll <= @drop_potion_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)

      true ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
    end
  end

  defp bits_to_f32(bits) do
    <<f::float-size(32)>> = <<bits::unsigned-size(32)>>
    f
  end

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
        Logger.warning(
          "[LEVEL UP] Renderer weapon '#{weapon_name}' not available. Falling back to #{inspect(fallback)}."
        )

        {:apply, fallback}

      true ->
        Logger.warning(
          "[LEVEL UP] Renderer weapon '#{weapon_name}' not available and no valid fallback. Skipping."
        )

        {:skip, :__skip__}
    end
  end

  defp close_level_up_scene_if_active(content, context, runner) do
    if function_exported?(content, :level_up_scene, 0) and runner do
      level_up_scene = content.level_up_scene()

      case Contents.SceneStack.current(runner) do
        {:ok, %{module: ^level_up_scene}} ->
          context.pop_scene.()

        _ ->
          :ok
      end
    end
  end

  defp call_nif(name, fun) do
    case fun.() do
      {:error, reason} ->
        Logger.error("[NIF ERROR] #{name} failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end
end
