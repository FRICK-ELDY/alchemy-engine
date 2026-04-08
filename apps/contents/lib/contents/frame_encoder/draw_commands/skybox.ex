defmodule Content.FrameEncoder.DrawCommands.Skybox do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:skybox, {tr, tg, tb, ta}, {br, bg, bb, ba}}) do
    %Alchemy.Render.DrawCommand{
      kind:
        {:skybox,
         %Alchemy.Render.SkyboxCmd{
           top_color: Proto.color_tuple_to_pb_list({tr, tg, tb, ta}),
           bottom_color: Proto.color_tuple_to_pb_list({br, bg, bb, ba})
         }}
    }
  end
end
