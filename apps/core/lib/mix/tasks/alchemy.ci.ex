defmodule Mix.Tasks.Alchemy.Ci do
  @shortdoc "ローカル CI 相当チェック（Rust + Elixir）"
  @moduledoc """
  GitHub Actions の CI と同等の検証をローカルで実行します。

  Elixir の **警告をエラーとして扱うコンパイル**は `mix test --warnings-as-errors` に含めます（`mix compile` を別起動すると、環境によって子プロセスの `MIX_ENV` がずれ `_build/dev` へコピーしようとして失敗することがあるため）。

  ## 引数（filter）

  - なし — 全ジョブ実行
  - `rust` — Rust のみ（fmt, clippy, test）
  - `elixir` — Elixir のみ（deps.get, format, credo, test。警告は test で `mix test --warnings-as-errors`）
  - `check` — フォーマット + Lint のみ（テストなし）

  ## 使用例

      mix alchemy.ci
      mix alchemy.ci rust
      mix alchemy.ci elixir
      mix alchemy.ci check
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    filter = List.first(args)
    root = File.cwd!()
    rust_manifest = Path.join(root, "rust/Cargo.toml")

    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  AlchemyEngine — Local CI")
    Mix.shell().info("  Mode: #{filter || "ALL"}")
    Mix.shell().info("========================================")

    failed =
      []
      |> rust_check(root, rust_manifest, filter)
      |> rust_test(root, rust_manifest, filter)
      |> elixir_check(root, filter)
      |> elixir_test(root, filter)

    Mix.shell().info("")
    Mix.shell().info("========================================")

    if failed == [] do
      Mix.shell().info("  RESULT: ALL PASSED")
      Mix.shell().info("========================================")
    else
      Mix.shell().error("  RESULT: FAILED — #{inspect(failed)}")
      Mix.shell().info("========================================")
      System.halt(1)
    end
  end

  defp rust_check(failed, root, manifest, filter) when filter != "elixir" do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [A] Rust — fmt & clippy")
    Mix.shell().info("========================================")

    failed =
      failed
      |> run_step("cargo fmt", fn ->
        System.cmd("cargo", ["fmt", "--manifest-path", manifest, "--all", "--", "--check"],
          cd: root,
          stderr_to_stdout: true
        )
      end)
      |> run_step("cargo clippy", fn ->
        System.cmd(
          "cargo",
          [
            "clippy",
            "--manifest-path",
            manifest,
            "--workspace",
            "--exclude",
            "launcher",
            "--",
            "-D",
            "warnings"
          ],
          cd: root,
          stderr_to_stdout: true
        )
      end)

    failed
  end

  defp rust_check(failed, _, _, _), do: failed

  defp rust_test(failed, root, manifest, filter) when filter != "elixir" and filter != "check" do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [B] Rust — unit tests (nif)")
    Mix.shell().info("========================================")
    Mix.shell().info("")
    Mix.shell().info("[STEP] cargo test -p nif")

    run_step(failed, "cargo test", fn ->
      System.cmd("cargo", ["test", "--manifest-path", manifest, "-p", "nif"],
        cd: root,
        stderr_to_stdout: true
      )
    end)
  end

  defp rust_test(failed, _, _, _), do: failed

  defp elixir_check(failed, root, filter) when filter != "rust" do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [C] Elixir — deps, format & credo")
    Mix.shell().info("========================================")

    failed =
      failed
      |> run_step("mix deps.get", fn ->
        mix_cmd(["deps.get"], root)
      end)
      |> run_step("mix format --check-formatted", fn ->
        mix_cmd(["format", "--check-formatted"], root)
      end)
      |> run_step("mix credo --strict", fn ->
        mix_cmd(["credo", "--strict"], root)
      end)

    failed
  end

  defp elixir_check(failed, _, _), do: failed

  defp elixir_test(failed, root, filter) when filter != "rust" and filter != "check" do
    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  [D] Elixir — mix test")
    Mix.shell().info("========================================")
    Mix.shell().info("")
    Mix.shell().info("[STEP] mix test")

    run_step(failed, "mix test", fn ->
      # compile --warnings-as-errors はここに含める（単独 compile は子プロセスの MIX_ENV が環境によって dev に落ちることがある）
      mix_cmd(["test", "--warnings-as-errors"], root)
    end)
  end

  defp elixir_test(failed, _, _), do: failed

  # MIX_ENV=test で子プロセスの mix を起動。[D] の test は GitHub elixir-test と同様。
  # System.cmd の :env は親プロセスの環境を継承しつつ上書き（PATH 等は維持される）。
  defp mix_cmd(args, root) when is_list(args) do
    System.cmd("elixir", ["-S", "mix"] ++ args,
      cd: root,
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}]
    )
  end

  defp run_step(failed, name, fun) do
    case fun.() do
      {_, 0} ->
        Mix.shell().info("[PASS] #{name}")
        failed

      {out, _} ->
        Mix.shell().error(out)
        failed ++ [name]
    end
  end
end
