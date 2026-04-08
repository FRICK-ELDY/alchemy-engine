defmodule Content.FrameEncoder.DrawCommands.GridPlane do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:grid_plane, size, divisions, {r, g, b, a}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:grid_plane,
         %Alchemy.Render.GridPlaneCmd{
           size: Proto.pb_float(size),
           divisions: divisions,
           color: Proto.color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end
end
