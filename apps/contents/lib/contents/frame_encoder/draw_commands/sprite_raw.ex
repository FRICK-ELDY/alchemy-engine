defmodule Content.FrameEncoder.DrawCommands.SpriteRaw do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb(
        {:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
      ) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:sprite_raw,
         %Alchemy.Render.SpriteRaw{
           x: Proto.pb_float(x),
           y: Proto.pb_float(y),
           width: Proto.pb_float(width),
           height: Proto.pb_float(height),
           uv_offset: Proto.vec2_to_pb_list({uv_ox, uv_oy}),
           uv_size: Proto.vec2_to_pb_list({uv_sx, uv_sy}),
           color_tint: Proto.color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end
end
