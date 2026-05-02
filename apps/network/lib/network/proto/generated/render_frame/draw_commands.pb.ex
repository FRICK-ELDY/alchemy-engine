defmodule Alchemy.Render.DrawCommand do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.DrawCommand",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :kind, 0

  field :player_sprite, 1, type: Alchemy.Render.PlayerSprite, json_name: "playerSprite", oneof: 0
  field :sprite_raw, 2, type: Alchemy.Render.SpriteRaw, json_name: "spriteRaw", oneof: 0
  field :particle, 3, type: Alchemy.Render.ParticleCmd, oneof: 0
  field :item, 4, type: Alchemy.Render.ItemCmd, oneof: 0
  field :obstacle, 5, type: Alchemy.Render.ObstacleCmd, oneof: 0
  field :box_3d, 6, type: Alchemy.Render.Box3dCmd, json_name: "box3d", oneof: 0
  field :grid_plane, 7, type: Alchemy.Render.GridPlaneCmd, json_name: "gridPlane", oneof: 0

  field :grid_plane_verts, 8,
    type: Alchemy.Render.GridPlaneVertsCmd,
    json_name: "gridPlaneVerts",
    oneof: 0

  field :skybox, 9, type: Alchemy.Render.SkyboxCmd, oneof: 0
  field :sphere_3d, 10, type: Alchemy.Render.Sphere3dCmd, json_name: "sphere3d", oneof: 0
  field :cone_3d, 11, type: Alchemy.Render.Box3dCmd, json_name: "cone3d", oneof: 0
end

defmodule Alchemy.Render.PlayerSprite do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.PlayerSprite",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :frame, 3, type: :uint32
end

defmodule Alchemy.Render.SpriteRaw do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.SpriteRaw",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :width, 3, type: :float
  field :height, 4, type: :float
  field :uv_offset, 5, repeated: true, type: :float, json_name: "uvOffset"
  field :uv_size, 6, repeated: true, type: :float, json_name: "uvSize"
  field :color_tint, 7, repeated: true, type: :float, json_name: "colorTint"
end

defmodule Alchemy.Render.ParticleCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.ParticleCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :r, 3, type: :float
  field :g, 4, type: :float
  field :b, 5, type: :float
  field :alpha, 6, type: :float
  field :size, 7, type: :float
end

defmodule Alchemy.Render.ItemCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.ItemCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :kind, 3, type: :uint32
end

defmodule Alchemy.Render.ObstacleCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.ObstacleCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :radius, 3, type: :float
  field :kind, 4, type: :uint32
end

defmodule Alchemy.Render.Box3dCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Box3dCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :z, 3, type: :float
  field :half_w, 4, type: :float, json_name: "halfW"
  field :half_h, 5, type: :float, json_name: "halfH"
  field :half_d, 6, type: :float, json_name: "halfD"
  field :color, 7, repeated: true, type: :float
end

defmodule Alchemy.Render.Sphere3dCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Sphere3dCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :x, 1, type: :float
  field :y, 2, type: :float
  field :z, 3, type: :float
  field :radius, 4, type: :float
  field :color, 5, repeated: true, type: :float
end

defmodule Alchemy.Render.GridPlaneCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.GridPlaneCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :size, 1, type: :float
  field :divisions, 2, type: :uint32
  field :color, 3, repeated: true, type: :float
end

defmodule Alchemy.Render.GridPlaneVertsCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.GridPlaneVertsCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :vertices, 1, repeated: true, type: Alchemy.Render.MeshVertex
end

defmodule Alchemy.Render.SkyboxCmd do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.SkyboxCmd",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :top_color, 1, repeated: true, type: :float, json_name: "topColor"
  field :bottom_color, 2, repeated: true, type: :float, json_name: "bottomColor"
end
