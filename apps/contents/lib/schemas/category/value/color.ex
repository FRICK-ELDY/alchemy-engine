defmodule Schemas.Category.Value.Color do
  @moduledoc """
  色型。拡張（RGBA 等）および 32 ビット詰め表現。
  """
  @type t :: {0..255, 0..255, 0..255, 0..255}
  @type t32 :: non_neg_integer()
end
