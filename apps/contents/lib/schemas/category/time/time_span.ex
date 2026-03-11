defmodule Schemas.Category.Time.TimeSpan do
  @moduledoc """
  時間幅型。期間をマイクロ秒単位の符号なし整数で表す。

  Value.ULong の範囲（0 〜 約 18.4 × 10¹⁸ μs ≒ 約 58 万年）を使用。
  """
  alias Schemas.Category.Value.ULong

  @type t :: ULong.t()
end
