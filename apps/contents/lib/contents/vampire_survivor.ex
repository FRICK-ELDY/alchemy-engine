defmodule Content.VampireSurvivor do
  alias Content.VampireSurvivor.EntityParams

  @moduledoc """
  ヴァンパイアサバイバーのコンテンツ定義。

  エンジンは `components/0` が返すコンポーネントリストを順に呼び出す。
  各コンポーネントは `Core.Component` ビヘイビアを実装する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Contents.Components.Category.Spawner,
      Content.VampireSurvivor.LevelComponent,
      Content.VampireSurvivor.BossComponent,
      Contents.Components.Category.Rendering.Render
    ]
  end

  def world_size, do: EntityParams.world_size()
  def world_params_for_nif, do: EntityParams.world_params_for_nif()
  def entity_params_for_nif, do: EntityParams.entity_params_for_nif()

  def build_frame(playing_state, context) do
    Content.VampireSurvivor.FrameBuilder.build(playing_state, context)
  end

  # ── シーン定義（エンジンが参照するシーン構成）────────────────────

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [
      %{scene_type: :playing, init_arg: %{}}
    ]
  end

  def physics_scenes do
    [:playing]
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :game_over
  def level_up_scene, do: :level_up
  def boss_alert_scene, do: :boss_alert

  def scene_init(:playing, init_arg), do: Content.VampireSurvivor.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.VampireSurvivor.GameOver.init(init_arg)
  def scene_init(:level_up, init_arg), do: Content.VampireSurvivor.LevelUp.init(init_arg)

  def scene_init(:boss_alert, init_arg),
    do: Content.VampireSurvivor.BossAlert.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.VampireSurvivor.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.VampireSurvivor.GameOver.update(context, state)
  end

  def scene_update(:level_up, context, state) do
    Content.VampireSurvivor.LevelUp.update(context, state)
  end

  def scene_update(:boss_alert, context, state) do
    Content.VampireSurvivor.BossAlert.update(context, state)
  end

  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :game_over
  def scene_render_type(:level_up), do: :level_up
  def scene_render_type(:boss_alert), do: :boss_alert

  defp map_transition_module_to_scene_type({:continue, state}), do: {:continue, state}

  defp map_transition_module_to_scene_type({:transition, {:push, mod, arg}, state}) do
    {:transition, {:push, scene_module_to_type(mod), arg}, state}
  end

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state}
  end

  defp scene_module_to_type(Content.VampireSurvivor.Playing), do: :playing
  defp scene_module_to_type(Content.VampireSurvivor.GameOver), do: :game_over
  defp scene_module_to_type(Content.VampireSurvivor.LevelUp), do: :level_up
  defp scene_module_to_type(Content.VampireSurvivor.BossAlert), do: :boss_alert
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Vampire Survivor"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録（EntityParams に委譲）────────────

  defdelegate assets_path, to: Content.VampireSurvivor.EntityParams
  defdelegate entity_registry, to: Content.VampireSurvivor.EntityParams
  defdelegate score_popup_lifetime, to: Content.VampireSurvivor.EntityParams
  defdelegate weapon_params, to: Content.VampireSurvivor.EntityParams

  @doc """
  R-P2: 敵接触の damage_this_frame リスト。[{kind_id, damage}, ...]。
  LevelComponent が on_nif_sync で set_enemy_damage_this_frame NIF に渡す。
  """
  def enemy_damage_this_frame(context) do
    dt = Map.get(context, :dt, 16 / 1000.0)

    EntityParams.enemy_damage_per_sec_list()
    |> Enum.map(fn {kind_id, damage_per_sec} -> {kind_id, damage_per_sec * dt} end)
  end

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── レベルアップ・武器選択（LevelSystem / Playing シーンに委譲）──

  defdelegate generate_weapon_choices(weapon_levels),
    to: Content.VampireSurvivor.Playing.LevelSystem

  defdelegate apply_level_up(scene_state, choices), to: Content.VampireSurvivor.Playing

  defdelegate apply_weapon_selected(scene_state, weapon),
    to: Content.VampireSurvivor.Playing

  defdelegate apply_level_up_skipped(scene_state), to: Content.VampireSurvivor.Playing

  def weapon_slots_for_nif(weapon_levels, weapon_cooldowns \\ %{}) do
    Content.VampireSurvivor.Playing.weapon_slots_for_nif(weapon_levels, weapon_cooldowns)
  end

  defdelegate accumulate_exp(state, exp), to: Content.VampireSurvivor.Playing
  defdelegate apply_boss_defeated(state), to: Content.VampireSurvivor.Playing

  # ── 報酬・スコア計算（EntityParams に委譲）──────────────────────

  defdelegate enemy_exp_reward(enemy_kind), to: Content.EntityParams
  defdelegate boss_exp_reward(boss_kind), to: Content.EntityParams
  defdelegate score_from_exp(exp), to: Content.EntityParams

  # ── ウェーブラベル（SpawnSystem に委譲）──────────────────────────

  defdelegate wave_label(elapsed_sec), to: Content.VampireSurvivor.SpawnSystem

  # ── セーブ/ロード用（weapon_slots SSoT 移行 Phase 4）───────────────

  @doc """
  セーブ用に weapon_levels を [%{kind_id: x, level: y}] 形式に変換する。
  """
  def weapon_levels_to_save_format(weapon_levels) when is_map(weapon_levels) do
    registry = entity_registry().weapons

    weapon_levels
    |> Enum.flat_map(fn {weapon_name, level} ->
      case Map.get(registry, weapon_name) do
        nil -> []
        kind_id -> [%{kind_id: kind_id, level: level}]
      end
    end)
  end

  @doc """
  ロード用に weapon_slots（[%{"kind_id"=>x,"level"=>y}]）を weapon_levels（%{name=>level}）に変換する。
  """
  def weapon_slots_to_levels(slots) when is_list(slots) do
    registry = entity_registry().weapons
    id_to_name = Enum.map(registry, fn {k, v} -> {v, k} end) |> Map.new()

    Enum.reduce(slots, %{}, fn ws, acc ->
      kid = ws["kind_id"] || ws[:kind_id]
      lv = ws["level"] || ws[:level]
      name = Map.get(id_to_name, kid)

      if name && lv, do: Map.put(acc, name, lv), else: acc
    end)
  end

  # ── シーン push 時の物理一時停止判定 ─────────────────────────────

  def pause_on_push?(scene_type) do
    scene_type in [:level_up, :boss_alert]
  end
end
