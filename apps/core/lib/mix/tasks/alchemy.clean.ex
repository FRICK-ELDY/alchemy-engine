defmodule Mix.Tasks.Alchemy.Clean do
  @shortdoc "依存関係・ビルド成果物を削除（_build, deps, native/target）"
  @moduledoc """
  Elixir と Rust のビルド成果物・依存関係を削除します。

  ## 削除対象

  - `_build/` — Elixir ビルド
  - `deps/` — Elixir 依存関係
  - `native/target/` — Rust ビルド

  ## オプション

  - `--force` — 確認なしで実行

  ## 使用例

      mix alchemy.clean
      mix alchemy.clean --force
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [force: :boolean])
    root = File.cwd!()

    dirs = [
      Path.join(root, "_build"),
      Path.join(root, "deps"),
      Path.join(root, "native/target")
    ]

    existing = Enum.filter(dirs, &File.exists?/1)

    if existing == [] do
      Mix.shell().info("削除するディレクトリはありません。")
    else
      proceed? =
        Keyword.get(opts, :force, false) or
          (
            Mix.shell().info("以下を削除します:")
            Enum.each(existing, &Mix.shell().info("  #{&1}"))
            Mix.shell().info("")
            Mix.shell().yes?("続行しますか?")
          )

      if proceed? do
        Enum.each(existing, fn dir ->
          Mix.shell().info("削除: #{dir}")
          File.rm_rf!(dir)
        end)

        Mix.shell().info("完了しました。")
      else
        Mix.shell().info("中断しました。")
      end
    end
  end
end
