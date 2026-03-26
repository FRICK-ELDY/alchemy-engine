defmodule Contents.Objects.Core.Struct do
  @moduledoc """
  オブジェクトの構造体。name, parent, tag, active, persistent, transform, components を保持する。

  ## parent の型について

  `parent` は親オブジェクトへの参照を表す。空間エンジン統合時に
  `pid()` / カスタム ID / `reference()` 等の具体的な型が確定する見込み。
  現時点では `term()` として汎用的に扱う。

  ## components について

  Object に紐づく Component モジュールのリスト。contents 層の build_frame / update 等から
  **主な入口**は `Contents.Objects.Components.run_components_for_objects/2`（Object リストを受け取る）。
  単一 Object の場合は `run_components/2` を直接呼ぶ。設計: workspace/2_todo/struct-node-component-object-linkage-plan.md
  """
  alias Structs.Category.Space.Transform

  @type t :: %__MODULE__{
          name: String.t(),
          parent: term() | nil,
          tag: String.t(),
          active: boolean(),
          persistent: boolean(),
          transform: Transform.t(),
          components: [module()]
        }

  defstruct name: "",
            parent: nil,
            tag: "",
            active: true,
            persistent: false,
            transform: Transform.new(),
            components: []

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
