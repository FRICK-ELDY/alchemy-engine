defmodule Contents.Behaviour.Objects do
  @moduledoc """
  Object 層の Behaviour。空間のピア（Entity）としての契約。

  ## 責務

  - **空間上の実体**: init、空間イベント対応。
  - **handle_cast**: 空間イベントの処理。
  - **子の管理**: コンポーネント・子 Object の管理。
  - **GenServer 規約**: `Contents.Behaviour` の制約に従う。
  """

  @callback handle_cast(event :: term(), state :: term()) ::
              {:noreply, term()} | {:stop, term(), term()}

  @optional_callbacks handle_cast: 2
end
