defmodule Content.SimpleBox3D do
  @moduledoc """
  シンプルな3Dゲームコンテンツ。

  Phase R-6: 3Dレンダリングパイプラインの動作検証用コンテンツ。

  - 青いボックス = プレイヤー（WASD移動）
  - 赤いボックス = 敵（プレイヤーを追跡）
  - グリッド地面
  - スカイボックス（空色グラデーション）
  - 固定カメラ（斜め上から俯瞰）

  Rust 側の物理エンジン（ECS）を使用せず、Elixir 側で3D座標を管理する。
  `push_render_frame` に `DrawCommand::Box3D` / `GridPlane` / `Skybox` を送ることで
  3Dパイプラインの動作を実証する。
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Contents.Components.Category.Spawner,
      Contents.Components.Category.Device.Mouse,
      Contents.Components.Category.Device.Keyboard,
      Contents.Components.Category.Rendering.Render
    ]
  end

  # Spawner が set_world_size に渡す。Rust 物理エンジンの physics_step が
  # map_size < PLAYER_SIZE（64.0px）でパニックしないよう十分な値を設定。
  def world_size, do: {2048.0, 2048.0}

  def build_frame(playing_state, context),
    do: Content.SimpleBox3D.Scenes.Playing.build_frame(playing_state, context)

  def mesh_definitions do
    [
      Contents.Components.Category.Procedural.Meshes.Box.mesh_def(),
      Contents.Components.Category.Procedural.Meshes.Quad.mesh_def()
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

  def scene_init(:playing, init_arg), do: Content.SimpleBox3D.Scenes.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.SimpleBox3D.Scenes.GameOver.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.SimpleBox3D.Scenes.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.SimpleBox3D.Scenes.GameOver.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :game_over

  defp map_transition_module_to_scene_type({:continue, state}), do: {:continue, state}

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state}
  end

  defp scene_module_to_type(Content.SimpleBox3D.Scenes.Playing), do: :playing
  defp scene_module_to_type(Content.SimpleBox3D.Scenes.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Simple Box 3D"
  def version, do: "0.1.0"

  # ── アセット（共通 LocalAssets を参照、アトラス不要）──────────────────

  def assets_path, do: ""

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "SimpleBox3D #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
