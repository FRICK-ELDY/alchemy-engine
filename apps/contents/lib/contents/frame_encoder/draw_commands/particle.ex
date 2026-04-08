defmodule Content.FrameEncoder.DrawCommands.Particle do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:particle, x, y, r, g, b, {alpha, size}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:particle,
         %Alchemy.Render.ParticleCmd{
           x: Proto.pb_float(x),
           y: Proto.pb_float(y),
           r: Proto.pb_float(r),
           g: Proto.pb_float(g),
           b: Proto.pb_float(b),
           alpha: Proto.pb_float(alpha),
           size: Proto.pb_float(size)
         }}
    }
  end
end
