defmodule Mix.Tasks.Alchemy.Gen.Proto do
  @shortdoc "proto/*.proto から Elixir / Rust の生成コードを作る（単一エントリ）"
  @moduledoc """
  `protoc` / `prost-build` による生成処理を **この Mix タスクに集約**する。

  OS ごとのシェルスクリプト（`scripts/*.sh` 等）は置かず、クロスプラットフォームで同じ手順にする。

  ## 実装状況

  生成ロジックは段階的に本モジュールへ追加する。詳細・契約・CI 要件は
  `workspace/2_todo/protobuf-full-automation-procedure.md` を参照。

  ## 使用例（予定）

      mix alchemy.gen.proto
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()
    proto_dir = Path.join(root, "proto")
    elixir_out = Path.join(root, "apps/network/lib/network/proto/generated")
    native_manifest = Path.join(root, "native/Cargo.toml")
    protoc = System.get_env("PROTOC") || "protoc"
    proto_files = discover_proto_files!(proto_dir)
    temp_out =
      Path.join([root, ".tmp", "alchemy-gen-proto-#{System.unique_integer([:positive])}"])

    Mix.shell().info("")
    Mix.shell().info("[alchemy.gen.proto] Protobuf 生成を開始します。")
    File.mkdir_p!(elixir_out)
    File.rm_rf!(temp_out)
    File.mkdir_p!(temp_out)

    try do
      run_step!(
        "protoc --elixir_out",
        protoc,
        protoc_args(proto_dir, temp_out, proto_files),
        root,
        env: [{"PATH", with_mix_escripts_in_path()}]
      )

      replace_generated_files!(temp_out, elixir_out)

      # Rust 側は build.rs 導入後、この cargo build が prost-build 生成のトリガーになる。
      run_step!(
        "cargo build -p network",
        "cargo",
        ["build", "--manifest-path", native_manifest, "-p", "network"],
        root
      )
    after
      File.rm_rf!(temp_out)
    end

    Mix.shell().info("[alchemy.gen.proto] 完了しました。")
    Mix.shell().info("")
  end

  defp protoc_args(proto_dir, elixir_out, proto_files) do
    [
      "--elixir_out=#{elixir_out}",
      "--proto_path=#{proto_dir}"
    ] ++ proto_files
  end

  defp discover_proto_files!(proto_dir) do
    proto_files =
      proto_dir
      |> Path.join("*.proto")
      |> Path.wildcard()
      |> Enum.sort()

    case proto_files do
      [] -> Mix.raise("`.proto` が見つかりません: #{proto_dir}")
      files -> files
    end
  end

  defp replace_generated_files!(temp_out, elixir_out) do
    generated =
      temp_out
      |> Path.join("**/*.pb.ex")
      |> Path.wildcard()
      |> Enum.sort()

    if generated == [] do
      Mix.raise("生成ファイルが作成されませんでした: #{temp_out}")
    end

    elixir_out
    |> Path.join("**/*.pb.ex")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)

    Enum.each(generated, fn src ->
      relative = Path.relative_to(src, temp_out)
      dst = Path.join(elixir_out, relative)
      dst |> Path.dirname() |> File.mkdir_p!()
      File.cp!(src, dst)
    end)
  end

  defp with_mix_escripts_in_path do
    current = System.get_env("PATH") || ""

    case System.user_home() do
      nil ->
        current

      home ->
        escripts = Path.join([home, ".mix", "escripts"])
        separator = if match?({:win32, _}, :os.type()), do: ";", else: ":"

        if String.contains?(current, escripts) do
          current
        else
          escripts <> separator <> current
        end
    end
  end

  defp run_step!(label, cmd, args, root, opts \\ []) do
    Mix.shell().info("")
    Mix.shell().info("[STEP] #{label}")
    env = Keyword.get(opts, :env, [])

    case System.cmd(cmd, args, cd: root, stderr_to_stdout: true, env: env) do
      {out, 0} ->
        if out != "" do
          Mix.shell().info(out)
        end

        :ok

      {out, code} ->
        Mix.shell().error(out)
        System.halt(code)
    end
  end
end
