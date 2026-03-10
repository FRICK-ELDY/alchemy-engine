defmodule Schemas.Category.Primitives.ULong do
  @moduledoc """
  符号なし 64 ビット整数型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: 0..18_446_744_073_709_551_615
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
