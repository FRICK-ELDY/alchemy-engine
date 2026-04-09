defmodule Content.FrameEncoder.DrawCommands.Obstacle do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:obstacle, x, y, radius, kind}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:obstacle,
         %Alchemy.Render.ObstacleCmd{
           x: Proto.pb_float(x),
           y: Proto.pb_float(y),
           radius: Proto.pb_float(radius),
           kind: kind
         }}
    }
  end
end
