defmodule Contents.Objects.Core.CreateEmptyChild do
  @moduledoc """
  空の子オブジェクトを作成する。親オブジェクトに紐づく空の子を追加する。

  実装は GenServer と空間イベントとの統合後に行う。現状はスタブ。
  戻り値の child の `parent` は未設定（nil）。親子関係は空間エンジン統合後に設定する。
  """
  alias Contents.Objects.Core.Struct

  @doc """
  親オブジェクトに対して空の子オブジェクトを作成する。

  親子関係は未設定。空間エンジン統合後に `parent` を紐づける。
  """
  @spec create(parent :: Struct.t(), opts :: keyword()) :: {:ok, Struct.t()} | {:error, term()}
  def create(%Struct{} = _parent, opts \\ []) do
    name = Keyword.get(opts, :name, "Child")
    # TODO: 空間エンジンとの統合後に親子関係を設定
    child = %Struct{name: name, parent: nil}
    {:ok, child}
  end
end
