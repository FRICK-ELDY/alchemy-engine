defmodule Structs.Category.Utility.Guid do
  @moduledoc """
  GUID（UUID）型。一意識別子。

  期待する形式: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"（RFC 4122 準拠の 36 文字文字列）。
  形式チェックは呼び出し側で行う。`@type t` は `String.t()` のため、厳密な形式検証は含まない。
  """
  @type t :: String.t()
end
