# client_desktop クロスコンパイル

`client_desktop` を各プラットフォーム向けにビルドする手順です。

## ネイティブビルド（推奨）

各 OS 上でその環境向けのバイナリを生成します。コマンドは同一です。

```bash
cargo build --release -p client_desktop
```

| プラットフォーム | 出力パス |
|:---|:---|
| Windows | `native/target/release/client_desktop.exe` |
| Linux | `native/target/release/client_desktop` |
| macOS | `native/target/release/client_desktop` |

`native/` ディレクトリで実行するか、`--manifest-path native/Cargo.toml` を指定してください。

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
cargo build --release -p client_desktop --manifest-path native/Cargo.toml \
  --target x86_64-pc-windows-gnu

# Linux 向け（macOS ホストから等）
cargo build --release -p client_desktop --manifest-path native/Cargo.toml \
  --target x86_64-unknown-linux-gnu

# macOS Intel 向け
cargo build --release -p client_desktop --manifest-path native/Cargo.toml \
  --target x86_64-apple-darwin

# macOS Apple Silicon (M1/M2 等) 向け
cargo build --release -p client_desktop --manifest-path native/Cargo.toml \
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
client_desktop.exe --connect tcp/127.0.0.1:7447 --room main

# Linux / macOS
./client_desktop --connect tcp/127.0.0.1:7447 --room main
```

詳細は [README の起動方法](../README.md#起動方法) を参照してください。

## 製品配布時のウィンドウ非表示（Windows）

### client_desktop exe

`cargo build --release` でビルドした exe は、`#![windows_subsystem = "windows"]` によりコンソールが表示されません。ゲームウィンドウのみが表示されます。

### zenohd

zenohd をバックグラウンドで非表示に起動する場合、VBScript ランチャーを使用します。

```batch
wscript.exe bin\run_zenohd_hidden.vbs
```

これで zenohd のコンソールウィンドウは表示されません。ランチャーバッチ内で呼び出せます。

**注意**: mix run（サーバー）は長時間実行のため、同様に非表示にすると問題発生時の確認が難しくなります。開発時はターミナルで起動し、製品運用時はサービス化や別プロセス管理を検討してください。
