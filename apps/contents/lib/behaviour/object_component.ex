defmodule Contents.Behaviour.ObjectComponent do
  @moduledoc """
  Object に紐づく Component の契約。

  コンテンツ単位でエンジンから呼ばれる `Core.Component` とは別に、
  Object に属する Component が実装する Behaviour。
  contents 層の build_frame / update 等から `Contents.Objects.Components.run_components/2` により
  `run/2` が呼ばれる。内部で Node と Struct を利用する。

  設計: docs/plan/current/struct-node-component-object-linkage-plan.md
  """

  @type object :: Contents.Objects.Core.Struct.t()
  @type context :: map()

  @doc """
  Object に紐づく Component の処理を実行する。

  object と context を受け取り、Node を呼び出して Struct を扱う等の処理を行う。
  戻り値は呼び出し元がマージしたり無視したりしてよい。
  """
  @callback run(object :: object(), context :: context()) :: term()

  @optional_callbacks run: 2
end
