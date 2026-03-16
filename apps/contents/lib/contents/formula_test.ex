defmodule Content.FormulaTest do
  @moduledoc """
  Formula エンジン検証コンテンツ。

  起動時に Contents.Nodes を用いて式を実行し、ノードアーキテクチャの動作を検証する。
  結果を HUD に表示する。

  ## 検証項目
  - 入力演算: player_x + player_y (1+2)
  - 定数演算: 10 + 3
  - 比較ノード: lt(a, b)
  - Store シミュレート: 0+1（read_store/write_store は未実装のため加算で代用）
  - 複数出力: x+y, x-y

  ## 起動方法
  config :server, :current, Content.FormulaTest
  """

  @behaviour Contents.Behaviour.Content

  def components do
    [
      Content.FormulaTest.InputComponent,
      Content.FormulaTest.RenderComponent
    ]
  end

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
    []
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :playing

  # Contents.Scenes ファサード経由。init_arg に module + payload を渡し、Scenes は定義を持たない。
  def scene_init(:playing, init_arg) do
    scene_init_arg = %{module: Content.FormulaTest.Playing, payload: init_arg}
    Contents.Scenes.init(scene_init_arg)
  end

  def scene_update(:playing, context, state) do
    Contents.Scenes.update(context, state)
  end

  # シーンの render_type に委譲。Stack の現 API は scene_type のみ渡すため、現時点では scene_type に対応するモジュールの render_type/0 を直接呼ぶ（init/update はファサード経由・render_type は非ファサード）。将来 Stack が state を渡す形になれば Contents.Scenes.render_type(state) に寄せる想定。
  def scene_render_type(:playing), do: Content.FormulaTest.Playing.render_type()

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
