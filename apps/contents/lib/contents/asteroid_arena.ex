defmodule Content.AsteroidArena do
  alias Content.AsteroidArena.SpawnComponent

  @moduledoc """
  AsteroidArena のコンテンツ定義。

  武器・ボス・レベルアップの概念を持たないシンプルなシューターコンテンツ。
  `level_up_scene/0`・`boss_alert_scene/0` を実装しないことで、
  エンジンコアがこれらの概念を持たなくても動作することを実証する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.AsteroidArena.SpawnComponent,
      Content.AsteroidArena.SplitComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [%{scene_type: :playing, init_arg: %{}}]
  end

  def physics_scenes do
    [:playing]
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :game_over

  def scene_init(:playing, init_arg), do: Content.AsteroidArena.Scenes.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.AsteroidArena.Scenes.GameOver.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.AsteroidArena.Scenes.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state),
    do: Content.AsteroidArena.Scenes.GameOver.update(context, state)

  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :game_over

  defp map_transition_module_to_scene_type({:continue, state}), do: {:continue, state}

  defp map_transition_module_to_scene_type({:continue, state, opts}),
    do: {:continue, state, opts || %{}}

  defp map_transition_module_to_scene_type({:transition, :pop, state}),
    do: {:transition, :pop, state}

  defp map_transition_module_to_scene_type({:transition, :pop, state, opts}),
    do: {:transition, :pop, state, opts || %{}}

  defp map_transition_module_to_scene_type({:transition, {:push, mod, arg}, state}) do
    {:transition, {:push, scene_module_to_type(mod), arg}, state}
  end

  defp map_transition_module_to_scene_type({:transition, {:push, mod, arg}, state, opts}) do
    {:transition, {:push, scene_module_to_type(mod), arg}, state, opts || %{}}
  end

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state}
  end

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state, opts}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state, opts || %{}}
  end

  defp scene_module_to_type(Content.AsteroidArena.Scenes.Playing), do: :playing
  defp scene_module_to_type(Content.AsteroidArena.Scenes.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Asteroid Arena"
  def version, do: "0.1.0"

  # ── アセット・エンティティ登録 ────────────────────────────────────

  defdelegate assets_path, to: Content.AsteroidArena.SpawnComponent
  defdelegate entity_registry, to: Content.AsteroidArena.SpawnComponent

  @doc """
  R-P2: 敵接触の damage_this_frame リスト。[{kind_id, damage}, ...]。
  SplitComponent が on_nif_sync で set_enemy_damage_this_frame NIF に渡す。
  """
  def enemy_damage_this_frame(context) do
    # GameEvents.build_context で必ず :dt が渡される。フォールバックは将来の変更に対する保険。
    dt = Map.get(context, :dt, 16 / 1000.0)

    SpawnComponent.enemy_damage_per_sec_list()
    |> Enum.map(fn {kind_id, damage_per_sec} -> {kind_id, damage_per_sec * dt} end)
  end

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── 報酬・スコア計算 ──────────────────────────────────────────────

  defdelegate enemy_exp_reward(enemy_kind),
    to: Content.AsteroidArena.SpawnSystem,
    as: :exp_reward

  defdelegate score_from_exp(exp), to: Content.AsteroidArena.SpawnSystem

  # ── ウェーブラベル ────────────────────────────────────────────────

  defdelegate wave_label(elapsed_sec), to: Content.AsteroidArena.SpawnSystem
end
