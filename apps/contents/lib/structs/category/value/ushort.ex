defmodule Structs.Category.Value.UShort do
  @moduledoc """
  符号なし 16 ビット整数型（0..65535）。スカラーおよび 2〜4 要素のベクトル。
  """
  @type t :: 0..65535
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
end
