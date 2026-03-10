defmodule Schemas.Category.Primitives.UInt do
  @moduledoc """
  符号なし 32 ビット整数型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: 0..4_294_967_295
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
