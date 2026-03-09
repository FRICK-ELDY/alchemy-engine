defmodule Mix.Tasks.Alchemy.Test do
  @shortdoc "Elixir と Rust を同時にテスト"
  @moduledoc """
  Elixir と Rust のテストを実行します。

  ## オプション

  - `--cover` — Elixir でカバレッジ付きテスト
  - `rust` — Rust のみ（cargo test -p nif）
  - `elixir` — Elixir のみ（mix test）

  ## 使用例

      mix alchemy.test
      mix alchemy.test --cover
      mix alchemy.test rust
      mix alchemy.test elixir
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [cover: :boolean])
    filter = List.first(rest)
    cover? = Keyword.get(opts, :cover, false)

    root = File.cwd!()
    native_manifest = Path.join(root, "native/Cargo.toml")

    failed =
      []
      |> maybe_rust_test(root, native_manifest, filter, cover?)
      |> maybe_elixir_test(root, filter, cover?)

    if failed == [] do
      Mix.shell().info("")
      Mix.shell().info("RESULT: ALL PASSED")
    else
      Mix.shell().error("RESULT: FAILED — #{inspect(failed)}")
      System.halt(1)
    end
  end

  defp maybe_rust_test(failed, root, manifest, filter, cover?)
       when filter != "elixir" and not cover? do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [A] Rust — cargo test (nif)")
    Mix.shell().info("========================================")
    Mix.shell().info("")
    Mix.shell().info("[STEP] cargo test -p nif")

    case System.cmd("cargo", ["test", "--manifest-path", manifest, "-p", "nif"],
           cd: root,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Mix.shell().info("[PASS] cargo test")
        failed

      {out, _} ->
        Mix.shell().error(out)
        failed ++ ["cargo test"]
    end
  end

  defp maybe_rust_test(failed, _, _, _, _), do: failed

  defp maybe_elixir_test(failed, root, filter, cover?) when filter != "rust" do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [B] Elixir — mix test")
    Mix.shell().info("========================================")
    Mix.shell().info("")

    step = if cover?, do: "mix test --cover", else: "mix test"
    Mix.shell().info("[STEP] #{step}")

    mix_args = if cover?, do: ["test", "--cover"], else: ["test"]

    case System.cmd("mix", mix_args, cd: root, stderr_to_stdout: true, env: [{"MIX_ENV", "test"}]) do
      {_, 0} ->
        Mix.shell().info("[PASS] mix test")
        failed

      {out, _} ->
        Mix.shell().error(out)
        failed ++ ["mix test"]
    end
  end

  defp maybe_elixir_test(failed, _, _, _), do: failed
end
