defmodule Content.FrameEncoder.DrawCommands.GridPlaneVerts do
  @moduledoc false

  alias Content.FrameEncoder.Proto

  def to_pb({:grid_plane_verts, vertices}) do
    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Alchemy.Render.MeshVertex{
          position: Proto.vec3_to_pb_list({px, py, pz}),
          color: Proto.color_tuple_to_pb_list({cr, cg, cb, ca})
        }
      end)

    %Alchemy.Render.DrawCommand{
      kind: {:grid_plane_verts, %Alchemy.Render.GridPlaneVertsCmd{vertices: verts}}
    }
  end
end
