defmodule Core.NifBridge.Behaviour do
  @moduledoc """
  `Core.NifBridge` の最小 Behaviour（式実行のみ）。Formula のモック等で利用する場合に限定。
  本番は `Core.NifBridge` が直接 NIF を呼ぶ。
  """

  @callback run_formula_bytecode(bytecode :: binary(), inputs :: map(), store_values :: map()) ::
              {:ok, {list(), map()}} | {:error, atom(), term()}
end
