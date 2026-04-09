defmodule Content.FrameEncoder.DrawCommands.PlayerSprite do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:player_sprite, x, y, frame}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:player_sprite,
         %Alchemy.Render.PlayerSprite{x: Proto.pb_float(x), y: Proto.pb_float(y), frame: frame}}
    }
  end
end
