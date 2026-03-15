defmodule Contents.Behaviour.Components do
  @moduledoc """
  Component 層の Behaviour。ノードを束ねて特定の機能を提供する契約。

  ## 責務

  - **状態保持**: コンポーネント固有の状態。
  - **ノード束ね**: 複数ノードを束ねるインターフェース。
  - **ライフサイクル**: on_ready、on_process など。
  - **GenServer 規約**: `Contents.Behaviour` の制約に従う。

  ## UI レイアウト系コンポーネントの責務分担（拡張時）

  - **LayoutElement**: 単一要素の幅・高さ・マージン等の制御。
  - **Layout** (Horizontal/Vertical/Grid): 子要素の配置ルールを提供。
  - **ContentsSizeFitter**: 子の内容に応じたレイアウト調整。
  """

  @callback on_ready(state :: term()) :: term()
  @callback on_process(state :: term(), delta :: term()) :: term()

  @optional_callbacks on_ready: 1, on_process: 2
end
