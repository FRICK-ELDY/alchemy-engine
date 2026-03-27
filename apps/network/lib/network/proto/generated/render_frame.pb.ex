defmodule Alchemy.Render.CursorGrabKind do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "alchemy.render.CursorGrabKind",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :CURSOR_GRAB_UNSPECIFIED, 0
  field :CURSOR_GRAB_GRAB, 1
  field :CURSOR_GRAB_RELEASE, 2
end

defmodule Alchemy.Render.RenderFrameEnvelope do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.RenderFrameEnvelope",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :payload, 1, type: :bytes
end

defmodule Alchemy.Render.RenderFrame do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.RenderFrame",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :commands, 1, repeated: true, type: Alchemy.Render.DrawCommand
  field :camera, 2, type: Alchemy.Render.CameraParams
  field :ui, 3, type: Alchemy.Render.UiCanvas

  field :mesh_definitions, 4,
    repeated: true,
    type: Alchemy.Render.MeshDef,
    json_name: "meshDefinitions"

  field :cursor_grab, 5,
    proto3_optional: true,
    type: Alchemy.Render.CursorGrabKind,
    json_name: "cursorGrab",
    enum: true
end

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

defmodule Alchemy.Render.MeshVertex do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.MeshVertex",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :position, 1, repeated: true, type: :float
  field :color, 2, repeated: true, type: :float
end

defmodule Alchemy.Render.MeshDef do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.MeshDef",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :vertices, 2, repeated: true, type: Alchemy.Render.MeshVertex
  field :indices, 3, repeated: true, type: :uint32
end

defmodule Alchemy.Render.CameraParams do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.CameraParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :kind, 0

  field :camera_2d, 1, type: Alchemy.Render.Camera2d, json_name: "camera2d", oneof: 0
  field :camera_3d, 2, type: Alchemy.Render.Camera3d, json_name: "camera3d", oneof: 0
end

defmodule Alchemy.Render.Camera2d do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Camera2d",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :offset_x, 1, type: :float, json_name: "offsetX"
  field :offset_y, 2, type: :float, json_name: "offsetY"
end

defmodule Alchemy.Render.Camera3d do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Camera3d",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :eye, 1, repeated: true, type: :float
  field :target, 2, repeated: true, type: :float
  field :up, 3, repeated: true, type: :float
  field :fov_deg, 4, type: :float, json_name: "fovDeg"
  field :near, 5, type: :float
  field :far, 6, type: :float
end

defmodule Alchemy.Render.UiCanvas do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiCanvas",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :nodes, 1, repeated: true, type: Alchemy.Render.UiNode
end

defmodule Alchemy.Render.UiNode do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiNode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :rect, 1, type: Alchemy.Render.UiRect
  field :component, 2, type: Alchemy.Render.UiComponent
  field :children, 3, repeated: true, type: Alchemy.Render.UiNode
end

defmodule Alchemy.Render.UiRect do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiRect",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :size, 0

  field :anchor, 1, type: :string
  field :offset, 2, repeated: true, type: :float
  field :wrap, 3, type: Alchemy.Render.UiSizeWrap, oneof: 0
  field :fixed, 4, type: Alchemy.Render.UiSizeFixed, oneof: 0
end

defmodule Alchemy.Render.UiSizeWrap do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiSizeWrap",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Alchemy.Render.UiSizeFixed do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiSizeFixed",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :w, 1, type: :float
  field :h, 2, type: :float
end

defmodule Alchemy.Render.UiComponent do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiComponent",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :kind, 0

  field :separator, 1, type: Alchemy.Render.UiSeparator, oneof: 0

  field :vertical_layout, 2,
    type: Alchemy.Render.UiVerticalLayout,
    json_name: "verticalLayout",
    oneof: 0

  field :horizontal_layout, 3,
    type: Alchemy.Render.UiHorizontalLayout,
    json_name: "horizontalLayout",
    oneof: 0

  field :rect, 4, type: Alchemy.Render.UiRectStyle, oneof: 0
  field :text, 5, type: Alchemy.Render.UiText, oneof: 0
  field :button, 6, type: Alchemy.Render.UiButton, oneof: 0
  field :progress_bar, 7, type: Alchemy.Render.UiProgressBar, json_name: "progressBar", oneof: 0
  field :spacing, 8, type: Alchemy.Render.UiSpacing, oneof: 0
  field :world_text, 9, type: Alchemy.Render.UiWorldText, json_name: "worldText", oneof: 0
  field :screen_flash, 10, type: Alchemy.Render.UiScreenFlash, json_name: "screenFlash", oneof: 0
end

defmodule Alchemy.Render.UiSeparator do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiSeparator",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3
end

defmodule Alchemy.Render.UiVerticalLayout do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiVerticalLayout",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :spacing, 1, type: :float
  field :padding, 2, repeated: true, type: :float
end

defmodule Alchemy.Render.UiHorizontalLayout do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiHorizontalLayout",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :spacing, 1, type: :float
  field :padding, 2, repeated: true, type: :float
end

defmodule Alchemy.Render.UiRectStyle do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiRectStyle",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :color, 1, repeated: true, type: :float
  field :corner_radius, 2, type: :float, json_name: "cornerRadius"
  field :border, 3, proto3_optional: true, type: Alchemy.Render.UiBorder
end

defmodule Alchemy.Render.UiBorder do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiBorder",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :color, 1, repeated: true, type: :float
  field :width, 2, type: :float
end

defmodule Alchemy.Render.UiText do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiText",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :text, 1, type: :string
  field :color, 2, repeated: true, type: :float
  field :size, 3, type: :float
  field :bold, 4, type: :bool
end

defmodule Alchemy.Render.UiButton do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiButton",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :label, 1, type: :string
  field :action, 2, type: :string
  field :color, 3, repeated: true, type: :float
  field :min_width, 4, type: :float, json_name: "minWidth"
  field :min_height, 5, type: :float, json_name: "minHeight"
end

defmodule Alchemy.Render.UiProgressBar do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiProgressBar",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :value, 1, type: :float
  field :max, 2, type: :float
  field :width, 3, type: :float
  field :height, 4, type: :float
  field :fg_color_high, 5, repeated: true, type: :float, json_name: "fgColorHigh"
  field :fg_color_mid, 6, repeated: true, type: :float, json_name: "fgColorMid"
  field :fg_color_low, 7, repeated: true, type: :float, json_name: "fgColorLow"
  field :bg_color, 8, repeated: true, type: :float, json_name: "bgColor"
  field :corner_radius, 9, type: :float, json_name: "cornerRadius"
end

defmodule Alchemy.Render.UiSpacing do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiSpacing",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :amount, 1, type: :float
end

defmodule Alchemy.Render.UiWorldText do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiWorldText",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :world_x, 1, type: :float, json_name: "worldX"
  field :world_y, 2, type: :float, json_name: "worldY"
  field :world_z, 3, type: :float, json_name: "worldZ"
  field :text, 4, type: :string
  field :color, 5, repeated: true, type: :float
  field :lifetime, 6, type: :float
  field :max_lifetime, 7, type: :float, json_name: "maxLifetime"
end

defmodule Alchemy.Render.UiScreenFlash do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiScreenFlash",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :color, 1, repeated: true, type: :float
end
