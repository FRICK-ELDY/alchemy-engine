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

  def flow_runner(_room_id), do: Process.whereis(Contents.SceneStack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [%{module: Content.AsteroidArena.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    [Content.AsteroidArena.Scenes.Playing]
  end

  def playing_scene, do: Content.AsteroidArena.Scenes.Playing
  def game_over_scene, do: Content.AsteroidArena.Scenes.GameOver

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
