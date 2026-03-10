defmodule Schemas.Category.Value.Byte do
  @moduledoc """
  符号なし 8 ビット整数型（0..255）。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: 0..255
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
