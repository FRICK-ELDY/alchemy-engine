defmodule Content.Telemetry do
  @moduledoc """
  Telemetry 表示コンテンツ。

  キーボード・マウスの入力状態を HUD でリアルタイム表示する。
  P5-2 MessagePack 検証やデバッグに利用する。

  ## 表示内容
  - keyboard: 押下中のキー（空白区切り）
  - mouse: x, y（絶対座標）, delta（相対移動量）

  ## 起動方法
  config :server, :current, Content.Telemetry
  mix run --no-halt
  """
  @behaviour Core.ContentBehaviour

  def components do
    [
      Contents.MenuComponent,
      Content.Telemetry.InputComponent,
      Content.Telemetry.RenderComponent
    ]
  end

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.SceneStack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [%{module: Content.Telemetry.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    []
  end

  def playing_scene, do: Content.Telemetry.Scenes.Playing
  def game_over_scene, do: Content.Telemetry.Scenes.Playing

  def title, do: "Telemetry"
  def version, do: "0.1.0"

  def assets_path, do: ""

  def entity_registry, do: %{weapons: %{}, enemies: %{}}

  def enemy_exp_reward(_kind_id), do: 0

  def score_from_exp(_exp), do: 0

  def context_defaults, do: %{}

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "Telemetry #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
