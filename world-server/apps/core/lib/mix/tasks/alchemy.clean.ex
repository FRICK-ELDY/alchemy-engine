defmodule Mix.Tasks.Alchemy.Clean do
  @shortdoc "依存関係・ビルド成果物を削除（_build, deps, rust/target）"
  @moduledoc """
  Elixir と Rust のビルド成果物・依存関係を削除します。

  ## 削除対象

  - `_build/` — Elixir ビルド
  - `deps/` — Elixir 依存関係
  - `rust/target/` — Rust ビルド

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
      Path.join(root, "rust/target")
    ]

    existing = Enum.filter(dirs, &File.exists?/1)

    cond do
      existing == [] ->
        Mix.shell().info("削除するディレクトリはありません。")

      confirm_delete?(opts, existing) ->
        do_delete(existing)
        Mix.shell().info("完了しました。")

      true ->
        Mix.shell().info("中断しました。")
    end
  end

  defp confirm_delete?(opts, existing) do
    force? = Keyword.get(opts, :force, false)
    force? or prompt_user(existing)
  end

  defp prompt_user(existing) do
    Mix.shell().info("以下を削除します:")
    Enum.each(existing, &Mix.shell().info("  #{&1}"))
    Mix.shell().info("")
    Mix.shell().yes?("続行しますか?")
  end

  defp do_delete(existing) do
    Enum.each(existing, fn dir ->
      Mix.shell().info("削除: #{dir}")
      File.rm_rf!(dir)
    end)
  end
end
