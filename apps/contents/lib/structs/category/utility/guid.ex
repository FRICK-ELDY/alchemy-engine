defmodule Structs.Category.Utility.Guid do
  @moduledoc """
  GUID（UUID）型。一意識別子。

  形式: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"（RFC 4122 準拠の 36 文字文字列）。
  """
  @type t :: String.t()
end
