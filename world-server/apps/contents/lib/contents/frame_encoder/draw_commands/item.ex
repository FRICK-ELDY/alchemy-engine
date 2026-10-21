defmodule Contents.FrameEncoder.DrawCommands.Item do
  @moduledoc false

  alias Contents.FrameEncoder.Proto

  def to_pb({:item, x, y, kind}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:item, %Alchemy.Render.ItemCmd{x: Proto.pb_double(x), y: Proto.pb_double(y), kind: kind}}
    }
  end
end
