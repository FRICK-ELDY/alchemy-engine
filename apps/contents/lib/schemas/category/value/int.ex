defmodule Schemas.Category.Value.Int do
  @moduledoc """
  符号付き 32 ビット整数型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: -2_147_483_648..2_147_483_647
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
