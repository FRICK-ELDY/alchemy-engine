defmodule Content.FrameEncoder.DrawCommands.Item do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:item, x, y, kind}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:item, %Alchemy.Render.ItemCmd{x: Proto.pb_float(x), y: Proto.pb_float(y), kind: kind}}
    }
  end
end
