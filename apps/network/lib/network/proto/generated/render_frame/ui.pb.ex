defmodule Alchemy.Render.UiCanvas do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiCanvas",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:nodes, 1, repeated: true, type: Alchemy.Render.UiNode)
end

defmodule Alchemy.Render.UiNode do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiNode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:rect, 1, type: Alchemy.Render.UiRect)
  field(:component, 2, type: Alchemy.Render.UiComponent)
  field(:children, 3, repeated: true, type: Alchemy.Render.UiNode)
end

defmodule Alchemy.Render.UiRect do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiRect",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:size, 0)

  field(:anchor, 1, type: :string)
  field(:offset, 2, repeated: true, type: :float)
  field(:wrap, 3, type: Alchemy.Render.UiSizeWrap, oneof: 0)
  field(:fixed, 4, type: Alchemy.Render.UiSizeFixed, oneof: 0)
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

  field(:w, 1, type: :float)
  field(:h, 2, type: :float)
end

defmodule Alchemy.Render.UiComponent do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiComponent",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof(:kind, 0)

  field(:separator, 1, type: Alchemy.Render.UiSeparator, oneof: 0)

  field(:vertical_layout, 2,
    type: Alchemy.Render.UiVerticalLayout,
    json_name: "verticalLayout",
    oneof: 0
  )

  field(:horizontal_layout, 3,
    type: Alchemy.Render.UiHorizontalLayout,
    json_name: "horizontalLayout",
    oneof: 0
  )

  field(:rect, 4, type: Alchemy.Render.UiRectStyle, oneof: 0)
  field(:text, 5, type: Alchemy.Render.UiText, oneof: 0)
  field(:button, 6, type: Alchemy.Render.UiButton, oneof: 0)
  field(:progress_bar, 7, type: Alchemy.Render.UiProgressBar, json_name: "progressBar", oneof: 0)
  field(:spacing, 8, type: Alchemy.Render.UiSpacing, oneof: 0)
  field(:world_text, 9, type: Alchemy.Render.UiWorldText, json_name: "worldText", oneof: 0)
  field(:screen_flash, 10, type: Alchemy.Render.UiScreenFlash, json_name: "screenFlash", oneof: 0)
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

  field(:spacing, 1, type: :float)
  field(:padding, 2, repeated: true, type: :float)
end

defmodule Alchemy.Render.UiHorizontalLayout do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiHorizontalLayout",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:spacing, 1, type: :float)
  field(:padding, 2, repeated: true, type: :float)
end

defmodule Alchemy.Render.UiRectStyle do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiRectStyle",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:color, 1, repeated: true, type: :float)
  field(:corner_radius, 2, type: :float, json_name: "cornerRadius")
  field(:border, 3, proto3_optional: true, type: Alchemy.Render.UiBorder)
end

defmodule Alchemy.Render.UiBorder do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiBorder",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:color, 1, repeated: true, type: :float)
  field(:width, 2, type: :float)
end

defmodule Alchemy.Render.UiText do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiText",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:text, 1, type: :string)
  field(:color, 2, repeated: true, type: :float)
  field(:size, 3, type: :float)
  field(:bold, 4, type: :bool)
end

defmodule Alchemy.Render.UiButton do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiButton",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:label, 1, type: :string)
  field(:action, 2, type: :string)
  field(:color, 3, repeated: true, type: :float)
  field(:min_width, 4, type: :float, json_name: "minWidth")
  field(:min_height, 5, type: :float, json_name: "minHeight")
end

defmodule Alchemy.Render.UiProgressBar do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiProgressBar",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:value, 1, type: :float)
  field(:max, 2, type: :float)
  field(:width, 3, type: :float)
  field(:height, 4, type: :float)
  field(:fg_color_high, 5, repeated: true, type: :float, json_name: "fgColorHigh")
  field(:fg_color_mid, 6, repeated: true, type: :float, json_name: "fgColorMid")
  field(:fg_color_low, 7, repeated: true, type: :float, json_name: "fgColorLow")
  field(:bg_color, 8, repeated: true, type: :float, json_name: "bgColor")
  field(:corner_radius, 9, type: :float, json_name: "cornerRadius")
end

defmodule Alchemy.Render.UiSpacing do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiSpacing",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:amount, 1, type: :float)
end

defmodule Alchemy.Render.UiWorldText do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiWorldText",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:world_x, 1, type: :float, json_name: "worldX")
  field(:world_y, 2, type: :float, json_name: "worldY")
  field(:world_z, 3, type: :float, json_name: "worldZ")
  field(:text, 4, type: :string)
  field(:color, 5, repeated: true, type: :float)
  field(:lifetime, 6, type: :float)
  field(:max_lifetime, 7, type: :float, json_name: "maxLifetime")
end

defmodule Alchemy.Render.UiScreenFlash do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.UiScreenFlash",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:color, 1, repeated: true, type: :float)
end
