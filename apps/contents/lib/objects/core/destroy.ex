defmodule Contents.Objects.Core.Destroy do
  @moduledoc """
  オブジェクトの破棄。指定したオブジェクトを空間から削除する。

  実装は GenServer と空間イベントとの統合後に行う。現状はスタブ。
  """
  alias Contents.Objects.Core.Struct

  @doc """
  オブジェクトを破棄する。

  子・コンポーネントも含めて破棄する想定。
  """
  @spec destroy(object :: Struct.t()) :: :ok | {:error, term()}
  def destroy(%Struct{} = _object) do
    # TODO: 空間エンジンとの統合後に実装
    :ok
  end
end
