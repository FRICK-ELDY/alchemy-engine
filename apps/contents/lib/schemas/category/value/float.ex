defmodule Schemas.Category.Value.Float do
  @moduledoc """
  32 ビット浮動小数型（単精度）のスキーマ。スカラー、2〜4 要素ベクトル、2x2〜4x4 行列、クォータニオン。

  Elixir の `float()` は 64 ビット（倍精度）ですが、本スキーマは 32 ビット精度を要求するコンテキスト
  （Resonite 等との相互運用、NIF 経由の値など）を意図しています。外部連携時は値域に注意してください。
  """
  @type t :: float()
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
  @type t2x2 :: {{t(), t()}, {t(), t()}}
  @type t3x3 :: {{t(), t(), t()}, {t(), t(), t()}, {t(), t(), t()}}
  @type t4x4 :: {{t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}}
  @type quaternion :: {t(), t(), t(), t()}
end
