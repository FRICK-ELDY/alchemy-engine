# client クロスコンパイル・ビルド

各 client（desktop / web / android / ios）をプラットフォーム向けにビルドする手順です。

## ネイティブビルド

各 OS 上でその環境向けのバイナリを生成します。コマンドは同一です。

```bash
cargo build --release -p app
```

| プラットフォーム | 出力パス |
|:---|:---|
| Windows | `native/target/release/VRAlchemy.exe` |
| Linux | `native/target/release/VRAlchemy` |
| macOS | `native/target/release/VRAlchemy` |

`mix alchemy.build` または `cargo build -p app` を使用してください。`native/` ディレクトリで実行するか、`--manifest-path native/Cargo.toml` を指定してください。

## クロスコンパイル

1 つのホスト環境から別の OS 向けにビルドする場合、ターゲットを指定します。

### ターゲットの追加

```bash
# Windows (GNU ツールチェーン)
rustup target add x86_64-pc-windows-gnu

# Linux
rustup target add x86_64-unknown-linux-gnu

# macOS (Intel)
rustup target add x86_64-apple-darwin

# macOS (Apple Silicon)
rustup target add aarch64-apple-darwin
```

### ビルドコマンド

```bash
# Windows 向け（Linux/macOS ホストから）
cargo build --release -p app --manifest-path native/Cargo.toml \
  --target x86_64-pc-windows-gnu

# Linux 向け（macOS ホストから等）
cargo build --release -p app --manifest-path native/Cargo.toml \
  --target x86_64-unknown-linux-gnu

# macOS Intel 向け
cargo build --release -p app --manifest-path native/Cargo.toml \
  --target x86_64-apple-darwin

# macOS Apple Silicon (M1/M2 等) 向け
cargo build --release -p app --manifest-path native/Cargo.toml \
  --target aarch64-apple-darwin
```

出力は `native/target/<target>/release/` に生成されます。

### クロスコンパイルの注意点

- **Windows**: GNU ターゲットは MinGW、MSVC ターゲットは `x86_64-pc-windows-msvc`（Visual Studio のリンカが必要）
- **Linux**: ホストが Linux でない場合、`x86_64-unknown-linux-gnu` 用のリンカ（例: `lld`）や C ライブラリの設定が必要なことがあります
- **macOS**: macOS 以外から macOS 向けにビルドするには、[osxcross](https://github.com/tpoechtrager/osxcross) 等の追加ツールが必要な場合があります

## 起動方法

ビルド後、サーバー（`mix run --no-halt`）と zenohd が起動している状態で:

```bash
# Windows
VRAlchemy.exe --connect tcp/127.0.0.1:7447 --room main

# Linux / macOS
./VRAlchemy --connect tcp/127.0.0.1:7447 --room main
```

詳細は [README の起動方法](../README.md#起動方法) を参照してください。

## 製品配布時のウィンドウ非表示（Windows）

### VRAlchemy exe

`cargo build --release` でビルドした exe は、`#![windows_subsystem = "windows"]` によりコンソールが表示されません。ゲームウィンドウのみが表示されます。

### zenohd

zenohd の起動は `mix alchemy.router` または `mix alchemy.launcher` から行えます。

**注意**: mix run（サーバー）は長時間実行のため、非表示で起動すると問題発生時の確認が難しくなります。開発時はターミナルで起動し、製品運用時はサービス化や別プロセス管理を検討してください。
