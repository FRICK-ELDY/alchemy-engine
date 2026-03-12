defmodule Contents.Objects.Core.Struct do
  @moduledoc """
  オブジェクトの構造体。name, parent, tag, active, persistent, transform を保持する。

  ## parent の型について

  `parent` は親オブジェクトへの参照を表す。空間エンジン統合時に
  `pid()` / カスタム ID / `reference()` 等の具体的な型が確定する見込み。
  現時点では `term()` として汎用的に扱う。
  """
  alias Structs.Category.Space.Transform

  @type t :: %__MODULE__{
          name: String.t(),
          parent: term() | nil,
          tag: String.t(),
          active: boolean(),
          persistent: boolean(),
          transform: Transform.t()
        }

  defstruct name: "",
            parent: nil,
            tag: "",
            active: true,
            persistent: false,
            transform: Transform.new()

  @doc "デフォルトのオブジェクト構造体を生成する。"
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc "指定のフィールドでオブジェクト構造体を生成する。"
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
