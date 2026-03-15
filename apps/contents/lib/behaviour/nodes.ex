defmodule Contents.Behaviour.Nodes do
  @moduledoc """
  Node 層の Behaviour。論理の原子としての契約。

  ## 責務

  - **Action/Logic ports**: action in/out, logic in/out の宣言。Link による接続先の参照。
  - **コールバック**: handle_pulse（パルス受信）、handle_sample（値の取得・変換）など。
  - **プロセス**: Node は GenServer 化しない。Component 内の Executor がグラフをトラバースし、コールバックを直接呼び出す。
  """

  @callback handle_pulse(pulse :: term(), context :: map()) ::
              :ok | {:ok, term()} | {:error, term()}
  @callback handle_sample(inputs :: map(), context :: map()) ::
              term() | {:ok, term()} | {:error, term()}

  @optional_callbacks handle_pulse: 2, handle_sample: 2
end
