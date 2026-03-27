# RenderFrame ネイティブ protobuf（proto/render_frame.proto と対応）
defmodule Network.Proto.RenderFrame do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :commands, 1, repeated: true, type: Network.Proto.DrawCommand
  field :camera, 2, type: Network.Proto.CameraParams
  field :ui, 3, type: Network.Proto.UiCanvas
  field :mesh_definitions, 4, repeated: true, type: Network.Proto.MeshDefMsg
  field :cursor_grab, 5, proto3_optional: true, type: Network.Proto.CursorGrabKind, enum: true
end

defmodule Network.Proto.DrawCommand do
  @moduledoc false
  use Protobuf, syntax: :proto3

  # protobuf 0.16+: ブロック形式 oneof は使えない。宣言 + 各 field に oneof: index を付ける。
  oneof :kind, 0

  field :player_sprite, 1, type: Network.Proto.PlayerSprite, oneof: 0
  field :sprite_raw, 2, type: Network.Proto.SpriteRaw, oneof: 0
  field :particle, 3, type: Network.Proto.ParticleCmd, oneof: 0
  field :item, 4, type: Network.Proto.ItemCmd, oneof: 0
  field :obstacle, 5, type: Network.Proto.ObstacleCmd, oneof: 0
  field :box_3d, 6, type: Network.Proto.Box3dCmd, oneof: 0
  field :grid_plane, 7, type: Network.Proto.GridPlaneCmd, oneof: 0
  field :grid_plane_verts, 8, type: Network.Proto.GridPlaneVertsCmd, oneof: 0
  field :skybox, 9, type: Network.Proto.SkyboxCmd, oneof: 0
end

defmodule Network.Proto.PlayerSprite do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :frame, 3, type: :uint32
end

defmodule Network.Proto.SpriteRaw do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :width, 3, type: :float
  field :height, 4, type: :float
  field :uv_offset, 5, repeated: true, type: :float
  field :uv_size, 6, repeated: true, type: :float
  field :color_tint, 7, repeated: true, type: :float
end

defmodule Network.Proto.ParticleCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :r, 3, type: :float
  field :g, 4, type: :float
  field :b, 5, type: :float
  field :alpha, 6, type: :float
  field :size, 7, type: :float
end

defmodule Network.Proto.ItemCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :kind, 3, type: :uint32
end

defmodule Network.Proto.ObstacleCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :radius, 3, type: :float
  field :kind, 4, type: :uint32
end

defmodule Network.Proto.Box3dCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :x, 1, type: :float
  field :y, 2, type: :float
  field :z, 3, type: :float
  field :half_w, 4, type: :float
  field :half_h, 5, type: :float
  field :half_d, 6, type: :float
  field :color, 7, repeated: true, type: :float
end

defmodule Network.Proto.GridPlaneCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :size, 1, type: :float
  field :divisions, 2, type: :uint32
  field :color, 3, repeated: true, type: :float
end

defmodule Network.Proto.GridPlaneVertsCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :vertices, 1, repeated: true, type: Network.Proto.MeshVertexMsg
end

defmodule Network.Proto.SkyboxCmd do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :top_color, 1, repeated: true, type: :float
  field :bottom_color, 2, repeated: true, type: :float
end

defmodule Network.Proto.MeshVertexMsg do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :position, 1, repeated: true, type: :float
  field :color, 2, repeated: true, type: :float
end

defmodule Network.Proto.MeshDefMsg do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :name, 1, type: :string
  field :vertices, 2, repeated: true, type: Network.Proto.MeshVertexMsg
  field :indices, 3, repeated: true, type: :uint32
end

defmodule Network.Proto.CameraParams do
  @moduledoc false
  use Protobuf, syntax: :proto3

  oneof :kind, 0

  field :camera_2d, 1, type: Network.Proto.Camera2d, oneof: 0
  field :camera_3d, 2, type: Network.Proto.Camera3d, oneof: 0
end

defmodule Network.Proto.Camera2d do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :offset_x, 1, type: :float
  field :offset_y, 2, type: :float
end

defmodule Network.Proto.Camera3d do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :eye, 1, repeated: true, type: :float
  field :target, 2, repeated: true, type: :float
  field :up, 3, repeated: true, type: :float
  field :fov_deg, 4, type: :float
  field :near, 5, type: :float
  field :far, 6, type: :float
end

defmodule Network.Proto.UiCanvas do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :nodes, 1, repeated: true, type: Network.Proto.UiNode
end

defmodule Network.Proto.UiNode do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :rect, 1, type: Network.Proto.UiRect
  field :component, 2, type: Network.Proto.UiComponent
  field :children, 3, repeated: true, type: Network.Proto.UiNode
end

defmodule Network.Proto.UiRect do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :anchor, 1, type: :string
  field :offset, 2, repeated: true, type: :float

  oneof :size, 0

  field :wrap, 3, type: Network.Proto.UiSizeWrap, oneof: 0
  field :fixed, 4, type: Network.Proto.UiSizeFixed, oneof: 0
end

defmodule Network.Proto.UiSizeWrap do
  @moduledoc false
  use Protobuf, syntax: :proto3
end

defmodule Network.Proto.UiSizeFixed do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :w, 1, type: :float
  field :h, 2, type: :float
end

defmodule Network.Proto.UiComponent do
  @moduledoc false
  use Protobuf, syntax: :proto3

  oneof :kind, 0

  field :separator, 1, type: Network.Proto.UiSeparator, oneof: 0
  field :vertical_layout, 2, type: Network.Proto.UiVerticalLayout, oneof: 0
  field :horizontal_layout, 3, type: Network.Proto.UiHorizontalLayout, oneof: 0
  field :rect, 4, type: Network.Proto.UiRectStyle, oneof: 0
  field :text, 5, type: Network.Proto.UiText, oneof: 0
  field :button, 6, type: Network.Proto.UiButton, oneof: 0
  field :progress_bar, 7, type: Network.Proto.UiProgressBar, oneof: 0
  field :spacing, 8, type: Network.Proto.UiSpacing, oneof: 0
  field :world_text, 9, type: Network.Proto.UiWorldText, oneof: 0
  field :screen_flash, 10, type: Network.Proto.UiScreenFlash, oneof: 0
end

defmodule Network.Proto.UiSeparator do
  @moduledoc false
  use Protobuf, syntax: :proto3
end

defmodule Network.Proto.UiVerticalLayout do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :spacing, 1, type: :float
  field :padding, 2, repeated: true, type: :float
end

defmodule Network.Proto.UiHorizontalLayout do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :spacing, 1, type: :float
  field :padding, 2, repeated: true, type: :float
end

defmodule Network.Proto.UiRectStyle do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :color, 1, repeated: true, type: :float
  field :corner_radius, 2, type: :float
  field :border, 3, proto3_optional: true, type: Network.Proto.UiBorder
end

defmodule Network.Proto.UiBorder do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :color, 1, repeated: true, type: :float
  field :width, 2, type: :float
end

defmodule Network.Proto.UiText do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :text, 1, type: :string
  field :color, 2, repeated: true, type: :float
  field :size, 3, type: :float
  field :bold, 4, type: :bool
end

defmodule Network.Proto.UiButton do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :label, 1, type: :string
  field :action, 2, type: :string
  field :color, 3, repeated: true, type: :float
  field :min_width, 4, type: :float
  field :min_height, 5, type: :float
end

defmodule Network.Proto.UiProgressBar do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :value, 1, type: :float
  field :max, 2, type: :float
  field :width, 3, type: :float
  field :height, 4, type: :float
  field :fg_color_high, 5, repeated: true, type: :float
  field :fg_color_mid, 6, repeated: true, type: :float
  field :fg_color_low, 7, repeated: true, type: :float
  field :bg_color, 8, repeated: true, type: :float
  field :corner_radius, 9, type: :float
end

defmodule Network.Proto.UiSpacing do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :amount, 1, type: :float
end

defmodule Network.Proto.UiWorldText do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :world_x, 1, type: :float
  field :world_y, 2, type: :float
  field :world_z, 3, type: :float
  field :text, 4, type: :string
  field :color, 5, repeated: true, type: :float
  field :lifetime, 6, type: :float
  field :max_lifetime, 7, type: :float
end

defmodule Network.Proto.UiScreenFlash do
  @moduledoc false
  use Protobuf, syntax: :proto3
  field :color, 1, repeated: true, type: :float
end
