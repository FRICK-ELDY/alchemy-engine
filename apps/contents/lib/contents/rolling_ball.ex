defmodule Content.RollingBall do
  @moduledoc """
  ローリングボール迷路コンテンツ。

  傾けた台の上でボールを転がし、穴に落ちないようにゴールを目指す3Dバランスゲーム。

  ## 設計方針
  - Rust 側に3D物理エンジンは使用しない
  - 重力・慣性・摩擦・衝突をすべて Elixir 側で近似計算する
  - DrawCommand::Box3D のみでボール・フロア・障害物・ゴールを表現する
  - ステージは3面（フロアサイズ・穴の数・障害物が異なる）

  ## シーン構成
  ```
  Title
    └──→ Playing（ステージ1）
              ├── ゴール到達 ──→ StageClear ──→ Playing（次ステージ）
              │                                      │
              │                               全ステージクリア
              │                                      │
              │                                   Ending
              └── 穴に落下 ──→ GameOver ──→ Playing（同ステージ リトライ）
  ```
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.RollingBall.SpawnComponent,
      Content.RollingBall.PhysicsComponent,
      Content.RollingBall.RenderComponent
    ]
  end

  # ── シーン定義 ────────────────────────────────────────────────────

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [%{scene_type: :title, init_arg: %{}}]
  end

  def physics_scenes do
    [:playing]
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :game_over

  def scene_init(:title, init_arg), do: Content.RollingBall.Scenes.Title.init(init_arg)
  def scene_init(:playing, init_arg), do: Content.RollingBall.Scenes.Playing.init(init_arg)
  def scene_init(:stage_clear, init_arg), do: Content.RollingBall.Scenes.StageClear.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.RollingBall.Scenes.GameOver.init(init_arg)
  def scene_init(:ending, init_arg), do: Content.RollingBall.Scenes.Ending.init(init_arg)

  def scene_update(:title, context, state) do
    Content.RollingBall.Scenes.Title.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:playing, context, state) do
    Content.RollingBall.Scenes.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:stage_clear, context, state) do
    Content.RollingBall.Scenes.StageClear.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.RollingBall.Scenes.GameOver.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:ending, context, state) do
    Content.RollingBall.Scenes.Ending.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_render_type(:title), do: :playing
  def scene_render_type(:playing), do: :playing
  def scene_render_type(:stage_clear), do: :playing
  def scene_render_type(:game_over), do: :game_over
  def scene_render_type(:ending), do: :playing

  defp map_transition_module_to_scene_type({:continue, state}), do: {:continue, state}
  defp map_transition_module_to_scene_type({:continue, state, opts}), do: {:continue, state, opts || %{}}
  defp map_transition_module_to_scene_type({:transition, :pop, state}), do: {:transition, :pop, state}
  defp map_transition_module_to_scene_type({:transition, :pop, state, opts}), do: {:transition, :pop, state, opts || %{}}
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

  defp scene_module_to_type(Content.RollingBall.Scenes.Title), do: :title
  defp scene_module_to_type(Content.RollingBall.Scenes.Playing), do: :playing
  defp scene_module_to_type(Content.RollingBall.Scenes.StageClear), do: :stage_clear
  defp scene_module_to_type(Content.RollingBall.Scenes.GameOver), do: :game_over
  defp scene_module_to_type(Content.RollingBall.Scenes.Ending), do: :ending
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Rolling Ball Maze"
  def version, do: "0.1.0"

  def assets_path, do: ""

  # ── エンティティレジストリ（RollingBall はエネミー・武器の概念なし）──

  def entity_registry, do: %{weapons: %{}, enemies: %{}}

  def enemy_exp_reward(_kind_id), do: 0

  def score_from_exp(_exp), do: 0

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "RollingBall #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
