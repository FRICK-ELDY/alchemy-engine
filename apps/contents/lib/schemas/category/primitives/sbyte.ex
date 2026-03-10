defmodule Schemas.Category.Primitives.SByte do
  @moduledoc """
  符号付き 8 ビット整数型（-128..127）。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: -128..127
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
