defmodule Contents.Core.Behaviour do
  @moduledoc """
  憲法。全層（Nodes, Components, Objects）が従う共通の土台。

  ## 責務

  - **GenServer の基盤**: Object / Component 層向けに init/terminate の雛形を提供。
    Node 層はプロセス化しないため適用外。
  - **プロセス識別子**: 共通の識別規則。
  - **共通型・コールバック**: 各層が参照する型定義とコールバックの雛形。

  ## 設計方針

  各層の Behaviour（nodes/core, components/core, objects/core）は本モジュールの
  制約に従う。`@behaviour` による直接指定は行わず、設計上の「従うべき原則」として扱う。
  """

  @type process_id :: term()
  @type world_ref :: reference()
  @type context :: map()
  @type event :: tuple()
end
