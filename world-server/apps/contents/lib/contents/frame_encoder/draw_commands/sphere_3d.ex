defmodule Contents.FrameEncoder.DrawCommands.Sphere3d do
  @moduledoc false

  alias Contents.FrameEncoder.Proto

  def to_pb({:sphere_3d, x, y, z, radius, {r, g, b, a}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:sphere_3d,
         %Alchemy.Render.Sphere3dCmd{
           x: Proto.pb_double(x),
           y: Proto.pb_double(y),
           z: Proto.pb_double(z),
           radius: Proto.pb_double(radius),
           color: Proto.color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end
end
