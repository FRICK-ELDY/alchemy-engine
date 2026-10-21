defmodule Mix.Tasks.Alchemy.Setup do
  @shortdoc "開発環境のセットアップ（deps.get + compile）"
  @moduledoc """
  開発環境のセットアップを行います。

  ## 実行内容

  1. `mix deps.get` — Elixir 依存関係の取得
  2. `mix compile` — コンパイル（NIF ビルド含む）

  ## 使用例

      mix alchemy.setup
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("deps.get")
    Mix.Task.run("compile")
    Mix.shell().info("セットアップ完了しました。")
  end
end
