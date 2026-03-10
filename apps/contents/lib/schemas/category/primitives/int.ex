defmodule Schemas.Category.Primitives.Int do
  @moduledoc """
  符号付き 32 ビット整数型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: integer()
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
