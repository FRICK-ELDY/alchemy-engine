defmodule Contents.Objects.Components do
  @moduledoc """
  Object に紐づく Component の実行ヘルパー。

  **主な入口**は `run_components_for_objects/2`（Object リストを受け取り、各 Object の components を実行）。
  単一 Object の場合は `run_components/2` を使用する。
  contents 層の build_frame / update 等から利用する。

  設計: docs/plan/current/struct-node-component-object-linkage-plan.md
  """

  alias Contents.Objects.Core.Struct, as: ObjectStruct

  @doc """
  単一 Object に紐づく Component をすべて実行する。

  `object.components` に含まれる各モジュールについて、`run(object, context)` を呼ぶ。
  モジュール以外（nil、文字列、未ロードの atom など）はスキップする。`run/2` を実装していないモジュールもスキップする。
  戻り値は集約せず無視する（副作用のみ想定）。object が nil の場合は何もしない。

  非 nil の object について、`Map.get(object, :components, [])` を用いているのは、
  古いデータや map 由来の object で `components` キーが無い場合の後方互換のため。
  """
  @spec run_components(ObjectStruct.t() | nil, map()) :: :ok
  def run_components(nil, _context), do: :ok

  def run_components(object, context) do
    components = Map.get(object, :components, [])

    Enum.each(components, fn mod ->
      if is_atom(mod) and mod != nil do
        case Code.ensure_loaded(mod) do
          {:module, _} ->
            if function_exported?(mod, :run, 2), do: mod.run(object, context)

          _ ->
            :ok
        end
      end
    end)

    :ok
  end

  @doc """
  トップレベル Object のリストに対して、各 Object の Component を実行する。

  **トップレベルのみ走査**: 再帰は行わない（Object 構造体に子リストがないため）。
  子 Object の Component は実行されない。将来子にも実行したい場合は本関数の仕様拡張が必要。
  リスト内の nil はスキップする（state.children の型が [term()] のため nil が混入し得る）。
  """
  @spec run_components_for_objects([ObjectStruct.t() | nil], map()) :: :ok
  def run_components_for_objects(objects, context) when is_list(objects) do
    Enum.each(objects, fn object -> run_components(object, context) end)
  end
end
