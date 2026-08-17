defmodule Content.SampleOsc do
  @moduledoc """
  OSC receive sample.

  Receives LittleOSC (iOS) floats (0.0 / 1.0) on UDP 10000 and maps them to box height.

  ## LittleOSC

  | Item | Value |
  | --- | --- |
  | Host | LAN IP shown on the HUD (`127.0.0.1` does not work from iPhone) |
  | Port | `10000` |
  | Messages | `/1/push1` `/1/push2` `/1/push3` `/1/push4` |
  | Type | float (0.0 or 1.0) |

  ## OSC Path

  | Path | Color |
  | --- | --- |
  | `/1/push1` | blue |
  | `/1/push2` | yellow |
  | `/1/push3` | red |
  | `/1/push4` | green |

  ## Start

      config :server, :current, Content.SampleOsc

  or `mix run --config config/sample_osc.exs`

  Render type is `scene_render_type/1` only (`Contents.Behaviour.Content`).
  """

  @behaviour Contents.Behaviour.Content

  def components do
    [
      Contents.Components.Category.Device.Keyboard,
      Contents.Components.Category.Rendering.Render
    ]
  end

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def on_quit_requested, do: System.stop(0)

  def build_frame(playing_state, context),
    do: Content.SampleOsc.Playing.build_frame(playing_state, context)

  def initial_scenes do
    [%{scene_type: :playing, init_arg: %{}}]
  end

  def physics_scenes do
    []
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :playing

  def scene_init(:playing, init_arg), do: Content.SampleOsc.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.SampleOsc.Playing.init(init_arg)

  def scene_update(:playing, context, state),
    do: Content.SampleOsc.Playing.update(context, state)

  def scene_update(:game_over, context, state),
    do: Content.SampleOsc.Playing.update(context, state)

  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :playing

  def title, do: "OSC Sample"
  def version, do: "0.1.0"

  def assets_path, do: ""

  def context_defaults, do: %{}

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "OSC #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
