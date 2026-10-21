defmodule Contents.Objects.Core.CreateEmptyParent do
  @moduledoc """
  空の親オブジェクトを作成する。指定したオブジェクトを子として持つ空の親を追加する。

  実装は GenServer と空間イベントとの統合後に行う。現状はスタブ。
  戻り値の親の `parent` は未設定（nil）。親子リンクは空間エンジン統合後に設定する。
  """
  alias Contents.Objects.Core.Struct

  @doc """
  子オブジェクトに対して空の親オブジェクトを作成する。

  親子関係は未設定。空間エンジン統合後に紐づける。
  """
  @spec create(child :: Struct.t(), opts :: keyword()) :: {:ok, Struct.t()} | {:error, term()}
  def create(%Struct{} = _child, opts \\ []) do
    name = Keyword.get(opts, :name, "Parent")
    # TODO: 空間エンジンとの統合後に親子関係を設定
    parent = %Struct{name: name, parent: nil}
    {:ok, parent}
  end
end
