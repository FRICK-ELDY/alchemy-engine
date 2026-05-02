defmodule Alchemy.Render.AudioFrame do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.AudioFrame",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :audio_cues, 1, repeated: true, type: :string, json_name: "audioCues"
end
