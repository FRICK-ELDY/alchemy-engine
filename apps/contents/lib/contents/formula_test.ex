defmodule Content.FormulaTest do
  @moduledoc """
  Formula エンジン検証コンテンツ。

  Elixir で式を定義（FormulaGraph）→ Rust で計算（NIF VM）→ Elixir で結果を受け取る
  フローを起動時に検証し、結果を画面に表示する。

  ## 検証項目
  - 入力演算: player_x + player_y
  - 定数演算: 10 + 3
  - 比較ノード: lt(a, b)
  - Store: read_store / write_store
  - 複数出力: x+y, x-y

  ## 起動方法
  config :server, :current, Content.FormulaTest
  """

  @behaviour Core.ContentBehaviour

  def components do
    [
      Content.FormulaTest.InputComponent,
      Content.FormulaTest.RenderComponent
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
    [%{module: Content.FormulaTest.Scenes.Playing, init_arg: %{}}]
  end

  def physics_scenes do
    []
  end

  def playing_scene, do: Content.FormulaTest.Scenes.Playing
  def game_over_scene, do: Content.FormulaTest.Scenes.Playing

  def title, do: "Formula Test"
  def version, do: "0.1.0"

  def assets_path, do: ""

  def entity_registry, do: %{weapons: %{}, enemies: %{}}

  def enemy_exp_reward(_kind_id), do: 0

  def score_from_exp(_exp), do: 0

  def context_defaults, do: %{}

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "FormulaTest #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
