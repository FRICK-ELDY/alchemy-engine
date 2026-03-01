defmodule GameContent.VampireSurvivor.LevelComponent do
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
  @behaviour GameEngine.Component

  require Logger

  @drop_magnet_threshold 2
  @drop_potion_threshold 7

  @item_gem GameContent.EntityParams.item_kind_gem()
  @item_potion GameContent.EntityParams.item_kind_potion()
  @item_magnet GameContent.EntityParams.item_kind_magnet()

  @potion_heal_value 20

  # ── on_frame_event: Rust フレームイベント処理 ──────────────────────

  @impl GameEngine.Component
  def on_frame_event({:enemy_killed, enemy_kind, x_bits, y_bits, _}, context) do
    content = GameEngine.Config.current()
    exp = content.enemy_exp_reward(enemy_kind)
    x = bits_to_f32(x_bits)
    y = bits_to_f32(y_bits)

    score_delta = apply_kill_to_scene(content, exp)

    call_nif(:add_score_popup, fn ->
      GameEngine.NifBridge.add_score_popup(context.world_ref, x, y, score_delta)
    end)

    spawn_item_drop(context.world_ref, enemy_kind, x, y, exp)

    :ok
  end

  def on_frame_event({:player_damaged, damage_x1000, _, _, _}, _context) do
    damage = damage_x1000 / 1000.0
    content = GameEngine.Config.current()

    GameEngine.SceneManager.update_by_module(content.playing_scene(), fn state ->
      new_hp = max(0.0, Map.get(state, :player_hp, 100.0) - damage)
      Map.put(state, :player_hp, new_hp)
    end)

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  # ── on_nif_sync: 毎フレーム NIF 注入 ─────────────────────────────

  @impl GameEngine.Component
  def on_nif_sync(context) do
    content = GameEngine.Config.current()
    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    sync_hud_state(context.world_ref, playing_state)
    sync_player_hp(context.world_ref, playing_state)
    sync_elapsed(context.world_ref, playing_state, context)
    sync_hud_level(context.world_ref, playing_state)
    sync_weapon_slots(context.world_ref, content, playing_state)

    :ok
  end

  # ── on_event: UI アクション・エンジン内部イベント ─────────────────

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

      GameEngine.SceneManager.update_by_module(
        content.playing_scene(),
        &content.apply_level_up_skipped/1
      )

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

          GameEngine.SceneManager.update_by_module(
            content.playing_scene(),
            &content.apply_weapon_selected(&1, weapon)
          )

        :skip ->
          GameEngine.SceneManager.update_by_module(
            content.playing_scene(),
            &content.apply_level_up_skipped/1
          )
      end

      close_level_up_scene_if_active(content, context)
    end

    :ok
  end

  def on_event({:ui_action, "__auto_pop__", scene_state}, _context) do
    content = GameEngine.Config.current()

    case scene_state do
      %{choices: [first | _]} ->
        Logger.info("[LEVEL UP] Auto-selected: #{inspect(first)} -> resuming")

        GameEngine.SceneManager.update_by_module(
          content.playing_scene(),
          &content.apply_weapon_selected(&1, first)
        )

      _ ->
        Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")

        GameEngine.SceneManager.update_by_module(
          content.playing_scene(),
          &content.apply_level_up_skipped/1
        )
    end

    :ok
  end

  def on_event(_event, _context), do: :ok

  # ── プライベート: NIF 同期 ────────────────────────────────────────

  defp sync_hud_state(world_ref, playing_state) do
    score = Map.get(playing_state, :score, 0)
    kill_count = Map.get(playing_state, :kill_count, 0)
    prev = Process.get({__MODULE__, :last_hud_state})
    new_val = {score, kill_count}

    if new_val != prev do
      call_nif(:set_hud_state, fn ->
        GameEngine.NifBridge.set_hud_state(world_ref, score, kill_count)
      end)

      Process.put({__MODULE__, :last_hud_state}, new_val)
    end
  end

  defp sync_player_hp(world_ref, playing_state) do
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    prev = Process.get({__MODULE__, :last_player_hp})

    if player_hp != prev do
      call_nif(:set_player_hp, fn ->
        GameEngine.NifBridge.set_player_hp(world_ref, player_hp)
      end)

      Process.put({__MODULE__, :last_player_hp}, player_hp)
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
        GameEngine.NifBridge.set_elapsed_seconds(world_ref, elapsed_ms / 1000.0)
      end)

      Process.put({__MODULE__, :last_elapsed_ms}, elapsed_ms)
    end
  end

  defp sync_hud_level(world_ref, playing_state) do
    case Map.get(playing_state, :level) do
      nil ->
        :ok

      level ->
        exp = Map.get(playing_state, :exp, 0)
        exp_to_next = Map.get(playing_state, :exp_to_next, 10)
        level_up_pending = Map.get(playing_state, :level_up_pending, false)
        weapon_choices = Map.get(playing_state, :weapon_choices, []) |> Enum.map(&to_string/1)
        new_val = {level, exp, exp_to_next, level_up_pending, weapon_choices}
        prev = Process.get({__MODULE__, :last_hud_level_state})

        if new_val != prev do
          call_nif(:set_hud_level_state, fn ->
            GameEngine.NifBridge.set_hud_level_state(
              world_ref,
              level,
              exp,
              exp_to_next,
              level_up_pending,
              weapon_choices
            )
          end)

          Process.put({__MODULE__, :last_hud_level_state}, new_val)
        end
    end
  end

  defp sync_weapon_slots(world_ref, content, playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels)
    prev = Process.get({__MODULE__, :last_weapon_levels})
    playing_scene = content.playing_scene()

    if weapon_levels != nil and weapon_levels != prev and
         function_exported?(playing_scene, :weapon_slots_for_nif, 1) do
      slots = playing_scene.weapon_slots_for_nif(weapon_levels)

      call_nif(:set_weapon_slots, fn ->
        GameEngine.NifBridge.set_weapon_slots(world_ref, slots)
      end)

      # NIF を実際に呼んだときだけダーティフラグを更新する
      Process.put({__MODULE__, :last_weapon_levels}, weapon_levels)
    end
  end

  # ── プライベート: フレームイベント処理ヘルパー ────────────────────

  defp apply_kill_to_scene(content, exp) do
    score_delta = content.score_from_exp(exp)

    # シーンが見つからない場合（Playing シーン以外での敵撃破等）は
    # update_by_module が何もしないため、score_delta のみ返して NIF ポップアップに使う
    GameEngine.SceneManager.update_by_module(content.playing_scene(), fn state ->
      state
      |> Map.update(:score, score_delta, &(&1 + score_delta))
      |> Map.update(:kill_count, 1, &(&1 + 1))
      |> content.playing_scene().accumulate_exp(exp)
    end)

    score_delta
  end

  defp spawn_item_drop(world_ref, _enemy_kind, x, y, exp) do
    roll = :rand.uniform(100)

    cond do
      roll <= @drop_magnet_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)

      roll <= @drop_potion_threshold ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)

      true ->
        GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
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

  defp call_nif(name, fun) do
    case fun.() do
      {:error, reason} ->
        Logger.error("[NIF ERROR] #{name} failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end
end
