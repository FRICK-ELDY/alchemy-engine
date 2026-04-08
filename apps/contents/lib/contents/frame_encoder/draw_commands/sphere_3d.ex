defmodule Content.FrameEncoder.DrawCommands.Sphere3d do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:sphere_3d, x, y, z, radius, {r, g, b, a}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:sphere_3d,
         %Alchemy.Render.Sphere3dCmd{
           x: Proto.pb_float(x),
           y: Proto.pb_float(y),
           z: Proto.pb_float(z),
           radius: Proto.pb_float(radius),
           color: Proto.color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end
end
