defmodule Schemas.Category.Primitives.Long do
  @moduledoc """
  符号付き 64 ビット整数型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: -9_223_372_036_854_775_808..9_223_372_036_854_775_807
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
