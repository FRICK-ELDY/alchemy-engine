defmodule Content.FrameEncoder.DrawCommands.Cone3d do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:cone_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:cone_3d,
         %Alchemy.Render.Box3dCmd{
           x: Proto.pb_float(x),
           y: Proto.pb_float(y),
           z: Proto.pb_float(z),
           half_w: Proto.pb_float(half_w),
           half_h: Proto.pb_float(half_h),
           half_d: Proto.pb_float(half_d),
           color: Proto.color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end
end
