defmodule Contents.FrameEncoder.DrawCommands.Obstacle do
  @moduledoc false

  alias Contents.FrameEncoder.Proto

  def to_pb({:obstacle, x, y, radius, kind}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:obstacle,
         %Alchemy.Render.ObstacleCmd{
           x: Proto.pb_double(x),
           y: Proto.pb_double(y),
           radius: Proto.pb_double(radius),
           kind: kind
         }}
    }
  end
end
