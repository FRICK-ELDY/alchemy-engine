defmodule Contents.ComponentList do
  @moduledoc """
  コンテンツのコンポーネントリスト解決。

  - local_user_input_module が未実装のコンテンツには Contents.LocalUserComponent を自動注入
  - Contents.TelemetryComponent を全コンテンツに注入し、入力状態を参照可能にする
  """

  @doc """
  有効なコンポーネントリストを返す。

  - local_user_input_module が返すモジュールが components に含まれていなければ先頭に注入
  - TelemetryComponent は常に先頭付近に注入（全コンテンツで get_input_state 利用可）
  """
  def components do
    content = Core.Config.current()
    base = content.components()
    local_mod = local_user_input_module(content)

    base
    |> ensure_contains(local_mod)
    |> ensure_contains(Contents.TelemetryComponent)
  end

  defp ensure_contains(list, mod) do
    if mod in list, do: list, else: [mod | list]
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
