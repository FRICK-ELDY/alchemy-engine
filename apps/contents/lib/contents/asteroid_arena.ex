defmodule Content.AsteroidArena do
  @moduledoc """
  AsteroidArena のコンテンツ定義。

  武器・ボス・レベルアップの概念を持たないシンプルなシューターコンテンツ。
  Phase 5 移行: Spawner + PhysicsEntity 共有コンポーネントを使用。
  Split ロジックは Playing に埋め込み。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Contents.Components.Category.Spawner,
      Contents.Components.Category.PhysicsEntity
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

  def scene_init(:playing, init_arg), do: Content.AsteroidArena.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.AsteroidArena.GameOver.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.AsteroidArena.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state),
    do: Content.AsteroidArena.GameOver.update(context, state)

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

  defp scene_module_to_type(Content.AsteroidArena.Playing), do: :playing
  defp scene_module_to_type(Content.AsteroidArena.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Asteroid Arena"
  def version, do: "0.1.0"

  # ── ワールド・エンティティ（Spawner 用）────────────────────────────

  def world_size, do: {2048.0, 2048.0}

  def entity_params_for_nif do
    {
      enemy_params(),
      [],
      []
    }
  end

  defp enemy_params do
    [
      # 0: Asteroid Large — 大型、低速、分裂する
      %{
        max_hp: 3.0,
        speed: 0.0,
        radius: 40.0,
        damage_per_sec: 15.0,
        render_kind: 20,
        particle_color: [0.7, 0.6, 0.5, 1.0],
        passes_obstacles: false
      },
      # 1: Asteroid Medium — 中型
      %{
        max_hp: 2.0,
        speed: 0.0,
        radius: 24.0,
        damage_per_sec: 10.0,
        render_kind: 21,
        particle_color: [0.65, 0.55, 0.45, 1.0],
        passes_obstacles: false
      },
      # 2: Asteroid Small — 小型、消滅のみ
      %{
        max_hp: 1.0,
        speed: 0.0,
        radius: 12.0,
        damage_per_sec: 5.0,
        render_kind: 22,
        particle_color: [0.6, 0.5, 0.4, 1.0],
        passes_obstacles: false
      },
      # 3: UFO — 高速、プレイヤーを追跡
      %{
        max_hp: 5.0,
        speed: 100.0,
        radius: 18.0,
        damage_per_sec: 20.0,
        render_kind: 23,
        particle_color: [0.2, 0.9, 0.8, 1.0],
        passes_obstacles: false
      }
    ]
  end

  # ── アセット・エンティティ登録 ────────────────────────────────────

  def assets_path, do: "asteroid_arena"

  def entity_registry do
    %{
      enemies: %{
        asteroid_large: 0,
        asteroid_medium: 1,
        asteroid_small: 2,
        ufo: 3
      },
      weapons: %{},
      bosses: %{}
    }
  end

  # ── PhysicsEntity 用コールバック ───────────────────────────────────

  @doc """
  R-P2: 敵接触の damage_this_frame リスト。[{kind_id, damage}, ...]。
  PhysicsEntity が on_nif_sync で frame_injection に注入する。
  """
  def enemy_damage_this_frame(context) do
    dt = Map.get(context, :dt, 16 / 1000.0)

    enemy_params()
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> {i, (p[:damage_per_sec] || 0) * dt} end)
  end

  @doc """
  敵撃破時の分裂・アイテムドロップ。PhysicsEntity が on_frame_event で呼ぶ。
  """
  def handle_enemy_killed(world_ref, kind_id, x, y) do
    Content.AsteroidArena.Playing.handle_split_and_drop(world_ref, kind_id, x, y)
  end

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # 被弾後の無敵時間（ms）。PhysicsEntity が player_damaged 処理で使用。
  def invincible_duration_ms, do: 500

  # ── 報酬・スコア計算 ──────────────────────────────────────────────

  def enemy_exp_reward(kind_id) do
    %{0 => 20, 1 => 10, 2 => 5, 3 => 50} |> Map.get(kind_id, 0)
  end

  def score_from_exp(exp), do: exp * 2

  # ── ウェーブラベル ────────────────────────────────────────────────

  def wave_label(elapsed_sec) do
    cond do
      elapsed_sec < 30 -> "Wave 1 - Asteroids"
      elapsed_sec < 90 -> "Wave 2 - Denser"
      elapsed_sec < 180 -> "Wave 3 - UFOs Appear"
      true -> "Wave 4 - Chaos"
    end
  end
end
