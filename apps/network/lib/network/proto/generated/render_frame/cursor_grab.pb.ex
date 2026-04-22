defmodule Alchemy.Render.CursorGrabKind do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "alchemy.render.CursorGrabKind",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:CURSOR_GRAB_UNSPECIFIED, 0)
  field(:CURSOR_GRAB_GRAB, 1)
  field(:CURSOR_GRAB_RELEASE, 2)
end
