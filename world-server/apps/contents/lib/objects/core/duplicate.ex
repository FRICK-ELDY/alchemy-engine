defmodule Contents.Objects.Core.Duplicate do
  @moduledoc """
  オブジェクトの複製。指定したオブジェクトのコピーを作成する。

  **現状はスタブ。** 実装は name と parent だけを変えたシャローコピー。
  将来的に GenServer と空間イベントとの統合後、子・コンポーネントを含む
  ディープコピーに置き換える想定。
  """
  alias Contents.Objects.Core.Struct

  @doc """
  オブジェクトを複製する。

  現状: name と parent のみ変更したシャローコピーを返す。
  将来: 子・コンポーネントを含むディープコピーを実装する想定。
  """
  @spec duplicate(object :: Struct.t()) :: {:ok, Struct.t()} | {:error, term()}
  def duplicate(%Struct{} = object) do
    # TODO: 空間エンジンとの統合後に実装
    duplicated = %Struct{
      object
      | name: "#{object.name}_copy",
        parent: nil
    }

    {:ok, duplicated}
  end
end
