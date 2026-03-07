defmodule Content.VampireSurvivor do
  alias Content.VampireSurvivor.SpawnComponent

  @moduledoc """
  ヴァンパイアサバイバーのコンテンツ定義。

  エンジンは `components/0` が返すコンポーネントリストを順に呼び出す。
  各コンポーネントは `Core.Component` ビヘイビアを実装する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.VampireSurvivor.LocalUserComponent,
      Content.VampireSurvivor.SpawnComponent,
      Content.VampireSurvivor.LevelComponent,
      Content.VampireSurvivor.BossComponent,
      Content.VampireSurvivor.RenderComponent
    ]
  end

  def local_user_input_module, do: Content.VampireSurvivor.LocalUserComponent

  # ── シーン定義（エンジンが参照するシーン構成）────────────────────

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.SceneStack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [
      %{module: Content.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  def physics_scenes do
    [Content.VampireSurvivor.Scenes.Playing]
  end

  def playing_scene, do: Content.VampireSurvivor.Scenes.Playing
  def game_over_scene, do: Content.VampireSurvivor.Scenes.GameOver
  def level_up_scene, do: Content.VampireSurvivor.Scenes.LevelUp
  def boss_alert_scene, do: Content.VampireSurvivor.Scenes.BossAlert

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Vampire Survivor"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録（SpawnComponent に委譲）──────────

  defdelegate assets_path, to: Content.VampireSurvivor.SpawnComponent
  defdelegate entity_registry, to: Content.VampireSurvivor.SpawnComponent

  @doc """
  R-P2: 敵接触の damage_this_frame リスト。[{kind_id, damage}, ...]。
  LevelComponent が on_nif_sync で set_enemy_damage_this_frame NIF に渡す。
  """
  def enemy_damage_this_frame(context) do
    # GameEvents.build_context で必ず :dt が渡される。フォールバックは将来の変更に対する保険。
    dt = Map.get(context, :dt, 16 / 1000.0)

    SpawnComponent.enemy_damage_per_sec_list()
    |> Enum.map(fn {kind_id, damage_per_sec} -> {kind_id, damage_per_sec * dt} end)
  end

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── レベルアップ・武器選択（LevelSystem / Playing シーンに委譲）──

  defdelegate generate_weapon_choices(weapon_levels), to: Content.VampireSurvivor.LevelSystem
  defdelegate apply_level_up(scene_state, choices), to: Content.VampireSurvivor.Scenes.Playing

  defdelegate apply_weapon_selected(scene_state, weapon),
    to: Content.VampireSurvivor.Scenes.Playing

  defdelegate apply_level_up_skipped(scene_state), to: Content.VampireSurvivor.Scenes.Playing

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

  def pause_on_push?(mod) do
    mod == Content.VampireSurvivor.Scenes.LevelUp or
      mod == Content.VampireSurvivor.Scenes.BossAlert
  end
end
