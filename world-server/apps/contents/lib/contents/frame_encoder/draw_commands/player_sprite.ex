defmodule Contents.FrameEncoder.DrawCommands.PlayerSprite do
  @moduledoc false

  alias Contents.FrameEncoder.Proto

  def to_pb({:player_sprite, x, y, frame}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:player_sprite,
         %Alchemy.Render.PlayerSprite{x: Proto.pb_double(x), y: Proto.pb_double(y), frame: frame}}
    }
  end
end
