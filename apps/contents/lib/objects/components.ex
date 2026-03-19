defmodule Contents.Objects.Components do
  @moduledoc """
  Object に紐づく Component の実行ヘルパー。

  Object の `components` フィールドに列挙されたモジュールの `run/2` を呼び出す。
  contents 層の build_frame / update 等から利用する。

  設計: docs/plan/current/struct-node-component-object-linkage-plan.md
  """

  alias Contents.Objects.Core.Struct, as: ObjectStruct

  @doc """
  単一 Object に紐づく Component をすべて実行する。

  `object.components` に含まれる各モジュールについて、`run(object, context)` を呼ぶ。
  `run/2` を実装していないモジュールはスキップする。戻り値は集約せず無視する（副作用のみ想定）。
  """
  @spec run_components(ObjectStruct.t(), map()) :: :ok
  def run_components(object, context) do
    for mod <- Map.get(object, :components, []) do
      if function_exported?(mod, :run, 2) do
        mod.run(object, context)
      end
    end

    :ok
  end

  @doc """
  トップレベル Object のリストに対して、各 Object の Component を実行する。

  再帰は行わない（Object 構造体に子リストがないため、トップレベルのみ）。
  """
  @spec run_components_for_objects([ObjectStruct.t()], map()) :: :ok
  def run_components_for_objects(objects, context) when is_list(objects) do
    for object <- objects do
      run_components(object, context)
    end

    :ok
  end
end
