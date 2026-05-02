defmodule Content.FrameEncoderAudioTest do
  use ExUnit.Case, async: true

  alias Content.FrameEncoder

  @minimal_camera {:camera_2d, 0.0, 0.0}
  @minimal_ui {:canvas, []}

  test "encode_frame に audio_cues を渡すとワイヤに載り decode で復元できる" do
    cues = ["assets/audio/player_hurt.wav"]
    bin = FrameEncoder.encode_frame([], @minimal_camera, @minimal_ui, [], nil, cues)

    assert %Alchemy.Render.RenderFrame{
             audio_frame: %Alchemy.Render.AudioFrame{audio_cues: ^cues}
           } = Alchemy.Render.RenderFrame.decode(bin)
  end
end
