defmodule Network.Proto.RenderFrameOneofTest do
  @moduledoc false
  use ExUnit.Case, async: true

  test "DrawCommand protobuf encodes sprite_raw oneof (regression: protobuf 0.16 explicit oneof)" do
    cmd = %Network.Proto.DrawCommand{
      kind:
        {:sprite_raw,
         %Network.Proto.SpriteRaw{
           x: 1.0,
           y: 2.0,
           width: 3.0,
           height: 4.0,
           uv_offset: [],
           uv_size: [],
           color_tint: []
         }}
    }

    assert byte_size(Protobuf.encode(cmd)) > 0
  end
end
