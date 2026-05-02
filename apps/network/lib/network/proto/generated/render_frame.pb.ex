defmodule Alchemy.Render.RenderFrameEnvelope do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.RenderFrameEnvelope",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :payload, 1, type: :bytes
end

defmodule Alchemy.Render.RenderFrame do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.RenderFrame",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :commands, 1, repeated: true, type: Alchemy.Render.DrawCommand
  field :camera, 2, type: Alchemy.Render.CameraParams
  field :ui, 3, type: Alchemy.Render.UiCanvas

  field :mesh_definitions, 4,
    repeated: true,
    type: Alchemy.Render.MeshDef,
    json_name: "meshDefinitions"

  field :cursor_grab, 5,
    proto3_optional: true,
    type: Alchemy.Render.CursorGrabKind,
    json_name: "cursorGrab",
    enum: true

  field :audio_frame, 6,
    proto3_optional: true,
    type: Alchemy.Render.AudioFrame,
    json_name: "audioFrame"
end
