# AlchemyEngine 開発ガイド

> 開発者向けのセットアップ・起動手順・開発支援をまとめています。

## 前提条件

- [Elixir](https://elixir-lang.org/install.html) **1.19 / OTP 28**
- [Rust](https://www.rust-lang.org/tools/install) (stable)
- [zenohd](https://github.com/eclipse-zenoh/zenohd)（リモート起動・一括起動時）:
  ```bash
  cargo install eclipse-zenoh
  ```

## セットアップ

1. リポジトリをクローンします。
   ```bash
   git clone git@github.com:FRICK-ELDY/alchemy-engine.git
   cd alchemy-engine
   ```

2. Elixir の依存関係を取得し、Rust のネイティブコードをコンパイルします。
   ```bash
   mix deps.get
   mix compile
   ```

## 起動方法

### ローカル起動（組み込み描画ウィンドウ）

サーバー内蔵の描画ウィンドウでゲームを表示します。

```bash
mix run --no-halt
```

### ランチャー（システムトレイ）

zenohd / HL-Server / Client をトレイメニューから管理します。Phase 0 ではトレイ表示と Quit のみ対応。

```bash
cargo run -p launcher
```

- トレイにアイコンが表示されます
- 右クリック → 「Quit」で終了

### クライアント exe のみでプレイ（一括起動）

zenohd、サーバー、クライアントを一括で起動します。

```bash
# Windows
bin\play.bat

# Linux / macOS
chmod +x bin/play.sh
./bin/play.sh
```

**前提**: zenohd をインストール済み（`cargo install eclipse-zenoh`）

### リモートクライアント起動（手動・3 ターミナル）

Zenoh 経由でサーバーとクライアントを分離して起動します。

1. ターミナル 1: zenohd を起動
   ```bash
   zenohd
   ```

2. ターミナル 2: サーバーを起動
   ```bash
   mix run --no-halt
   ```

3. ターミナル 3: デスクトップクライアントを起動
   ```bash
   # Windows
   bin\windows_client.bat

   # Linux / macOS
   cargo run -p desktop_client -- --connect tcp/127.0.0.1:7447 --room main
   ```

接続先やルームを変更する場合:  
`bin\windows_client.bat tcp/127.0.0.1:7447 main`

### 分散クラスタ起動（複数ノード）

`config/runtime.exs` に libcluster の topologies を設定し、別ターミナルで各ノードを起動します。

```bash
# ターミナル 1
elixir --name a@127.0.0.1 -S mix run

# ターミナル 2
elixir --name b@127.0.0.1 -S mix run
```

## 品質保証・開発コマンド

| 対象 | コマンド | 内容 |
|:---|:---|:---|
| Rust コードスタイル | `cargo fmt` | フォーマット統一 |
| Rust 静的解析 | `cargo clippy -D warnings` | 警告ゼロ |
| Rust ユニットテスト | `cargo test` | 物理演算ロジックの正確性 |
| Elixir コードスタイル | `mix format` | フォーマット統一 |
| Elixir 静的解析 | `mix credo --strict` | コード品質・一貫性 |
| Elixir コンパイル | `mix compile --warnings-as-errors` | 警告ゼロ |
| Elixir 統合テスト | `mix test` | Elixir/Rust 結合の動作保証 |

CI の詳細は [docs/warranty/ci.md](./docs/warranty/ci.md) を参照。

## 関連ドキュメント

- [ビジョンと設計思想](./docs/vision.md)
- [クライアント・サーバー分離手順](./docs/plan/client-server-separation-procedure.md)
- [ランチャー設計](./docs/plan/launcher-design.md)
- [クライアント exe のビルド・クロスコンパイル](./docs/cross-compile.md)
