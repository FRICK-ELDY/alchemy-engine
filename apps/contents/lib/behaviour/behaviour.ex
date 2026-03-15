defmodule Contents.Behaviour do
  @moduledoc """
  憲法。全層（Content, Scene, Object, Component, Node）が従う共通の土台。

  ## 責務

  - **GenServer の基盤**: Object / Component 層向けに init/terminate の雛形を提供。
    Node 層はプロセス化しないため適用外。
  - **プロセス識別子**: 共通の識別規則。
  - **共通型・コールバック**: 各層が参照する型定義とコールバックの雛形。

  ## 設計方針

  各層の契約は Contents.Behaviour.Scenes, .Objects, .Nodes, .Components, .Content で定義する。
  `@behaviour` による直接指定は本モジュールには行わず、設計上の「従うべき原則」として扱う。

  ## 旧モジュール名（削除済み）

  - 憲法: `Contents.Core.Behaviour`（旧 `core/behaviour.ex`）
  - Scene: `Contents.Scenes.Core.Behaviour`（旧 `scenes/core/behaviour.ex`）
  - Object: `Contents.Objects.Core.Behaviour`（旧 `objects/core/behaviour.ex`）
  - Node: `Contents.Nodes.Core.Behaviour`（旧 `nodes/core/behaviour.ex`）
  - Component: `Contents.Components.Core.Behaviour`（旧 `components/core/behaviour.ex`）
  """

  @type process_id :: term()
  @type world_ref :: reference()
  @type context :: map()
  @type event :: tuple()
end
