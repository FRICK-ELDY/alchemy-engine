defmodule Network.Proto.CursorGrabKind do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3

  field :CURSOR_GRAB_UNSPECIFIED, 0
  field :CURSOR_GRAB_GRAB, 1
  field :CURSOR_GRAB_RELEASE, 2
end
