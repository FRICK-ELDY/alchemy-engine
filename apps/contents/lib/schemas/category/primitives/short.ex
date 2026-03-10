defmodule Schemas.Category.Primitives.Short do
  @moduledoc """
  符号付き 16 ビット整数型（-32768..32767）。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: -32768..32767
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
