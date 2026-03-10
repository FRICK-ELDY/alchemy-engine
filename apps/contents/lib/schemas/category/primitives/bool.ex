defmodule Schemas.Category.Primitives.Bool do
  @moduledoc """
  真偽値型。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: boolean()
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
