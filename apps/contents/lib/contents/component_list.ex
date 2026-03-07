defmodule Contents.ComponentList do
  @moduledoc """
  コンテンツのコンポーネントリスト解決。

  local_user_input_module が未実装のコンテンツには
  Contents.LocalUserComponent を自動注入し、全コンテンツが LocalUserComponent 経由で
  キーボード・マウス入力を取得する。
  """

  @doc """
  有効なコンポーネントリストを返す。

  local_user_input_module が返すモジュールが components に含まれていなければ、
  先頭に注入する。
  """
  def components do
    content = Core.Config.current()
    base = content.components()
    mod = local_user_input_module(content)

    if mod in base do
      base
    else
      [mod | base]
    end
  end

  @doc """
  ローカルユーザー入力モジュールを返す。

  content が local_user_input_module/0 を実装しない場合は
  Contents.LocalUserComponent を返す。
  """
  def local_user_input_module(content \\ Core.Config.current()) do
    if function_exported?(content, :local_user_input_module, 0) do
      content.local_user_input_module() || Contents.LocalUserComponent
    else
      Contents.LocalUserComponent
    end
  end
end
