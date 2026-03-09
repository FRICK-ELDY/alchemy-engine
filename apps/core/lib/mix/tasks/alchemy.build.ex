defmodule Mix.Tasks.Alchemy.Build do
  @shortdoc "app クレート（VRAlchemy）をビルド"
  @moduledoc """
  app クレート（VRAlchemy バイナリ）をビルドします。

  ## オプション

  - `--release` — リリースビルド（デフォルト: debug）
  - `--desktop` — デスクトップ向け（現状はこれのみ対応）

  ## 使用例

      mix alchemy.build
      mix alchemy.build --release
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [release: :boolean, desktop: :boolean])
    release? = Keyword.get(opts, :release, false)
    profile = if release?, do: "release", else: "debug"

    root = File.cwd!()
    manifest = Path.join(root, "native/Cargo.toml")

    Mix.shell().info("")
    Mix.shell().info("Building app (VRAlchemy) (#{profile})...")
    Mix.shell().info("")

    cargo_args = ["build", "--manifest-path", manifest, "-p", "app"]
    cargo_args = if release?, do: cargo_args ++ ["--release"], else: cargo_args

    case System.cmd("cargo", cargo_args, cd: root, stderr_to_stdout: true) do
      {out, 0} ->
        Mix.shell().info(out)
        Mix.shell().info("ビルド完了しました。")

      {out, code} ->
        Mix.shell().error(out)
        System.halt(code)
    end
  end
end
