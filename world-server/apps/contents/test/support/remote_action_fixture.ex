defmodule Contents.Events.RemoteActionFixture do
  @moduledoc false

  defdelegate components, to: Content.SampleOsc
  defdelegate flow_runner(room_id), to: Content.SampleOsc
  defdelegate event_handler(room_id), to: Content.SampleOsc
  defdelegate game_over_scene, to: Content.SampleOsc
  defdelegate playing_scene, to: Content.SampleOsc
  defdelegate physics_scenes, to: Content.SampleOsc
  defdelegate context_defaults, to: Content.SampleOsc
  defdelegate wave_label(elapsed), to: Content.SampleOsc
  defdelegate scene_update(type, context, state), to: Content.SampleOsc
  defdelegate scene_render_type(type), to: Content.SampleOsc
  defdelegate scene_init(type, arg), to: Content.SampleOsc
  defdelegate initial_scenes, to: Content.SampleOsc

  def ui_action_handlers do
    %{
      "__ping__" => {:playing, fn state -> Map.put(state, :pinged, true) end},
      "__quit__" => {:playing, fn state -> Map.put(state, :quit_ran, true) end}
    }
  end
end
