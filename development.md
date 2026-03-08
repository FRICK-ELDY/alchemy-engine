# AlchemyEngine 開発ガイド

> 開発者向けのセットアップ・起動手順・開発支援をまとめています。

## 前提条件

- [Elixir](https://elixir-lang.org/install.html) **1.19 / OTP 28**
- [Rust](https://www.rust-lang.org/tools/install) (stable)
- [zenohd](https://github.com/eclipse-zenoh/zenohd)（リモート起動・一括起動時）:
  ```bash
  cargo install eclipse-zenoh
  ```

### 環境変数 PATH（ランチャー利用時）

ランチャーから Phoenix Server を起動するには、**Elixir の bin を PATH に含める**必要があります。

- **Windows**: システムの環境変数 PATH に Elixir の bin を追加
  - 例: `C:\Program Files\Elixir\bin` または `C:\Program Files (x86)\Elixir\bin`
  - 設定後はランチャーを再起動
- **Linux / macOS**: 通常はインストール時に PATH に追加済み

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

zenohd / HL-Server / Client をトレイメニューから管理します（Phase 0–6 対応）。

```bash
cargo run -p launcher
```

- トレイにアイコンが表示されます
- **Zenoh Router** →「Run」で zenohd を起動（ポート 7447 の応答を確認）
- **Zenoh Router** →「Quit」で zenohd を終了
- **Phoenix Server** →「Run」で mix run を起動（ポート 4000 の応答を確認）
- **Phoenix Server** →「Quit」で mix run を終了
- **Client Run** → zenohd と Phoenix Server の起動を確認してから desktop_client を起動
- **Check for Update...** → GitHub releases で最新版を確認
- **acknowledgements** → 謝辞・ライセンス一覧を表示
- 起動中は Run 無効・Quit 有効。両方起動時はアイコン緑、それ以外は灰色
- 起動失敗時はダイアログで通知
- 「Quit」でランチャーを終了

**前提**: ランチャーは `current_dir` または exe の親階層から mix.exs を検索する。そのためプロジェクトルート直下でなく、サブディレクトリから起動しても見つかる場合がある。また、Elixir の bin を PATH に含める（上記「環境変数 PATH」参照）。

zenohd の稼働確認（PowerShell）:

```powershell
Get-Process zenohd -ErrorAction SilentlyContinue
```

プロセスが返れば起動中、何も返らなければ未起動。

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
| Rust パフォーマンス | `cargo bench` | main への push 時に CI でリグレッション検知（+10% 超でブロック） |
| Elixir コードスタイル | `mix format` | フォーマット統一 |
| Elixir 静的解析 | `mix credo --strict` | コード品質・一貫性 |
| Elixir コンパイル | `mix compile --warnings-as-errors` | 警告ゼロ |
| Elixir 統合テスト | `mix test` | Elixir/Rust 結合の動作保証 |

CI の詳細は [docs/warranty/ci.md](./docs/warranty/ci.md) を参照。

## 関連ドキュメント

- [ビジョンと設計思想](./docs/vision.md)
- [クライアント・サーバー分離手順](./docs/plan/client-server-separation-procedure.md)
- [ランチャー課題・設計](./docs/plan/improvement-plan.md#i-g-ランチャーlauncherの課題)（[launcher-design_do.md](./docs/plan/launcher-design_do.md) 実施計画）
- [クライアント exe のビルド・クロスコンパイル](./docs/cross-compile.md)
