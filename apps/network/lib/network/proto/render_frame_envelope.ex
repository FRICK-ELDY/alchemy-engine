defmodule Network.Proto.RenderFrameEnvelope do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :payload, 1, type: :bytes
end
