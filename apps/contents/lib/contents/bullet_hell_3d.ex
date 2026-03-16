defmodule Content.BulletHell3D do
  @moduledoc """
  3D 弾幕避けゲームコンテンツ。

  SimpleBox3D の3Dパイプラインを基盤に、弾幕避けゲームプレイを追加する。
  Elixir 側で3D座標・弾・敵を管理し、Rust 物理エンジンは使用しない。

  ## ゲームルール
  - プレイヤー（青ボックス）は WASD で XZ 平面上を移動
  - 敵（赤ボックス）がフィールド外周から出現し、プレイヤーに向かって直進
  - 敵が定期的にプレイヤー方向へ弾（黄ボックス）を発射
  - 弾または敵に当たると HP -1（HP = 3）
  - HP が 0 になるとゲームオーバー
  - 時間経過とともに敵数・発射間隔がスケールアップ
  """

  # ── コンポーネントリスト ──────────────────────────────────────────

  def components do
    [
      Content.BulletHell3D.SpawnComponent,
      Content.BulletHell3D.InputComponent,
      Content.BulletHell3D.BulletComponent,
      Content.BulletHell3D.DamageComponent,
      Content.BulletHell3D.RenderComponent
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

  def scene_init(:playing, init_arg), do: Content.BulletHell3D.Scenes.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.BulletHell3D.Scenes.GameOver.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.BulletHell3D.Scenes.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.BulletHell3D.Scenes.GameOver.update(context, state)
    |> map_transition_module_to_scene_type()
  end

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

  defp scene_module_to_type(Content.BulletHell3D.Scenes.Playing), do: :playing
  defp scene_module_to_type(Content.BulletHell3D.Scenes.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  # ── メタ情報 ──────────────────────────────────────────────────────

  def title, do: "Bullet Hell 3D"
  def version, do: "0.1.0"

  # ── アセット（共通 LocalAssets を参照、アトラス不要）──────────────────

  def assets_path, do: ""

  # ── コンテキストデフォルト ────────────────────────────────────────

  def context_defaults, do: %{}

  # ── ウェーブラベル（Diagnostics ログ用）──────────────────────────

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "BulletHell3D #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
