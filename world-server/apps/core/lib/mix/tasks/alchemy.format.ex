defmodule Mix.Tasks.Alchemy.Format do
  @shortdoc "Elixir と Rust を同時にフォーマット"
  @moduledoc """
  Elixir と Rust のコードをフォーマットします。

  ## オプション

  - `--check` — フォーマット差分のチェックのみ（変更なし）
  - `rust` — Rust のみ
  - `elixir` — Elixir のみ

  ## 使用例

      mix alchemy.format
      mix alchemy.format --check
      mix alchemy.format rust
      mix alchemy.format elixir
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [check: :boolean])
    filter = List.first(rest)
    check? = Keyword.get(opts, :check, false)

    root = File.cwd!()
    rust_manifest = Path.join(root, "rust/Cargo.toml")

    failed =
      []
      |> maybe_rust_fmt(root, rust_manifest, filter, check?)
      |> maybe_elixir_format(root, filter, check?)

    if failed == [] do
      Mix.shell().info("")
      Mix.shell().info("RESULT: #{if check?, do: "ALL FORMATTED", else: "ALL DONE"}")
    else
      Mix.shell().error("RESULT: FAILED — #{inspect(failed)}")
      System.halt(1)
    end
  end

  defp maybe_rust_fmt(failed, root, manifest, filter, check?) when filter != "elixir" do
    step = if check?, do: "cargo fmt --check", else: "cargo fmt"
    Mix.shell().info("")
    Mix.shell().info("[STEP] #{step}")

    args =
      ["fmt", "--manifest-path", manifest, "--all", "--"] ++ if(check?, do: ["--check"], else: [])

    case System.cmd("cargo", args, cd: root, stderr_to_stdout: true) do
      {_, 0} ->
        Mix.shell().info("[PASS] cargo fmt")
        failed

      {out, _} ->
        Mix.shell().error(out)
        failed ++ ["cargo fmt"]
    end
  end

  defp maybe_rust_fmt(failed, _, _, _, _), do: failed

  defp maybe_elixir_format(failed, root, filter, check?) when filter != "rust" do
    step = if check?, do: "mix format --check-formatted", else: "mix format"
    Mix.shell().info("")
    Mix.shell().info("[STEP] #{step}")

    if check? do
      case System.cmd("mix", ["format", "--check-formatted"], cd: root, stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("[PASS] mix format")
          failed

        {out, _} ->
          Mix.shell().error(out)
          failed ++ ["mix format"]
      end
    else
      Mix.Task.run("format", [])
      Mix.shell().info("[PASS] mix format")
      failed
    end
  end

  defp maybe_elixir_format(failed, _, _, _), do: failed
end
