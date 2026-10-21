defmodule Mix.Tasks.Alchemy.Gen.Proto do
  @shortdoc "PROTOCOL_PIN / PROTO_ROOT の .proto から Elixir 生成コードを作る"
  @moduledoc """
  `protoc` による **Elixir** 生成を **この Mix タスクに集約**する。

  Rust クライアント（prost）は [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client) 側。

  ## `.proto` の場所（優先順）

  1. 環境変数 **`PROTO_ROOT`**（`.proto` を含むディレクトリ）
  2. 未設定時はリポジトリ直下の **`PROTOCOL_PIN`** に従い、
     `.proto-cache/alchemy-protocol-<tag>/` へ git clone（R2）

  旧 `3rdparty/alchemy-protocol` は廃止。親スーパープロジェクトの `protocol/` を使う場合は
  必ず `PROTO_ROOT` を明示すること（例: `set PROTO_ROOT=%CD%\\..\\protocol\\proto`）。

  ## 使用例

      mix alchemy.gen.proto
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()
    proto_dir = resolve_proto_dir!(root)
    elixir_out = Path.join(root, "apps/network/lib/network/proto/generated")
    protoc = System.get_env("PROTOC") || "protoc"
    proto_files = discover_proto_files!(proto_dir)

    temp_out =
      Path.join([root, ".tmp", "alchemy-gen-proto-#{System.unique_integer([:positive])}"])

    Mix.shell().info("")
    Mix.shell().info("[alchemy.gen.proto] Protobuf 生成を開始します（Elixir のみ）。")
    Mix.shell().info("[alchemy.gen.proto] PROTO_ROOT=#{proto_dir}")
    Mix.shell().info("[alchemy.gen.proto] Rust クライアント生成は alchemy-client 側で行ってください。")
    File.mkdir_p!(elixir_out)
    File.rm_rf!(temp_out)
    File.mkdir_p!(temp_out)

    try do
      run_step_or_raise!(
        "protoc --elixir_out",
        protoc,
        protoc_args(proto_dir, temp_out, proto_files),
        root,
        env: [{"PATH", with_mix_escripts_in_path()}]
      )

      replace_generated_files!(temp_out, elixir_out)
    after
      File.rm_rf!(temp_out)
    end

    Mix.shell().info("[alchemy.gen.proto] 完了しました。")
    Mix.shell().info("")
  end

  defp protoc_args(proto_dir, elixir_out, proto_files) do
    base = Path.expand(proto_dir)

    rel_inputs =
      Enum.map(proto_files, fn p ->
        p |> Path.expand() |> Path.relative_to(base)
      end)

    [
      "--elixir_out=#{elixir_out}",
      "--proto_path=#{base}"
    ] ++ rel_inputs
  end

  defp resolve_proto_dir!(root) do
    dir =
      case System.get_env("PROTO_ROOT") do
        nil -> ensure_proto_cache!(root)
        p -> Path.expand(p, root)
      end

    unless File.dir?(dir) do
      Mix.raise(
        "Protobuf スキーマディレクトリが見つかりません: #{dir}\n" <>
          "PROTO_ROOT を設定するか、PROTOCOL_PIN に従う git clone が成功するか確認してください。"
      )
    end

    dir
  end

  defp ensure_proto_cache!(root) do
    pin = read_protocol_pin!(root)
    cache_repo = Path.join([root, ".proto-cache", "alchemy-protocol-#{pin.tag}"])
    proto_dir = Path.join(cache_repo, "proto")

    if File.dir?(proto_dir) and git_head_matches?(cache_repo, pin.sha) do
      proto_dir
    else
      File.rm_rf!(cache_repo)
      File.mkdir_p!(Path.dirname(cache_repo))

      Mix.shell().info("[alchemy.gen.proto] fetching #{pin.url} @ #{pin.tag} into #{cache_repo}")

      case System.cmd(
             "git",
             ["clone", "--depth", "1", "--branch", pin.tag, pin.url, cache_repo],
             stderr_to_stdout: true
           ) do
        {out, 0} ->
          if out != "", do: Mix.shell().info(out)

        {out, code} ->
          Mix.shell().error(out)
          Mix.raise("git clone of alchemy-protocol failed (exit #{code})")
      end

      unless git_head_matches?(cache_repo, pin.sha) do
        Mix.raise("PROTOCOL_PIN sha mismatch after clone (tag=#{pin.tag})")
      end

      proto_dir
    end
  end

  defp read_protocol_pin!(root) do
    path = Path.join(root, "PROTOCOL_PIN")

    unless File.exists?(path) do
      Mix.raise("PROTOCOL_PIN が見つかりません: #{path}")
    end

    kv =
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        line = String.trim(line)

        cond do
          line == "" or String.starts_with?(line, "#") ->
            acc

          String.contains?(line, "=") ->
            [k, v] = String.split(line, "=", parts: 2)
            Map.put(acc, String.trim(k), String.trim(v))

          true ->
            acc
        end
      end)

    %{
      tag: require_nonempty!(kv, "tag"),
      sha: require_nonempty!(kv, "sha"),
      url: require_nonempty!(kv, "url")
    }
  end

  defp require_nonempty!(kv, key) do
    case Map.get(kv, key) do
      nil -> Mix.raise("PROTOCOL_PIN missing #{key}=")
      "" -> Mix.raise("PROTOCOL_PIN #{key}= must not be empty")
      value -> value
    end
  end

  defp git_head_matches?(repo, pin_sha) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: repo, stderr_to_stdout: true) do
      {out, 0} ->
        head = out |> String.trim() |> String.downcase()
        pin = pin_sha |> String.trim() |> String.downcase()

        if pin == "" do
          false
        else
          head == pin or String.starts_with?(head, pin) or String.starts_with?(pin, head)
        end

      _ ->
        false
    end
  end

  defp discover_proto_files!(proto_dir) do
    proto_files =
      proto_dir
      |> Path.join("**/*.proto")
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

  defp run_step_or_raise!(label, cmd, args, root, opts) do
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
        Mix.raise("#{label} が失敗しました (exit #{code})")
    end
  end
end
