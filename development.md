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

2. 開発環境のセットアップを実行します。
   ```bash
   mix deps.get
   mix alchemy.setup
   ```

### Rust NIF（`native/nif`）

`mix compile` のたびに Rustler が **`native/nif` を release ビルド**し、`Core.NifBridge` にリンクします。現行 NIF は **Formula 用 `run_formula_bytecode` のみ**（ゲーム物理・ECS 用 NIF は撤去済み）。ワークスペース単体の検証例:

```bash
cd native && cargo build -p nif -p app
```

## 起動方法

### サーバー単体起動

```bash
mix alchemy.server
```

または `mix run --no-halt`

`mix run` 単体ではウィンドウは開かず、サーバーのみ起動します。ゲームをプレイするには zenohd と VRAlchemy（デスクトップクライアント）を別途起動してください。

### ランチャー（システムトレイ）

zenohd / HL-Server / Client をトレイメニューから管理します（Phase 0–6 対応）。

```bash
mix alchemy.launcher
```

- トレイにアイコンが表示されます
- **Zenoh Router** →「Run」で zenohd を起動（ポート 7447 の応答を確認）
- **Zenoh Router** →「Quit」で zenohd を終了
- **Phoenix Server** →「Run」で mix run を起動（ポート 4000 の応答を確認）
- **Phoenix Server** →「Quit」で mix run を終了
- **Client Run** → zenohd と Phoenix Server の起動を確認してから VRAlchemy（デスクトップクライアント）を起動
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

ランチャー（`mix alchemy.launcher`）を使用して zenohd、サーバー、クライアントを管理します。

**前提**: zenohd をインストール済み（`cargo install eclipse-zenoh`）

### リモートクライアント起動（手動・3 ターミナル）

Zenoh 経由でサーバーとクライアントを分離して起動します。

1. ターミナル 1: zenohd を起動
   ```bash
   mix alchemy.router
   ```

2. ターミナル 2: サーバーを起動
   ```bash
   mix alchemy.server
   ```

3. ターミナル 3: デスクトップクライアントを起動
   ```bash
   mix alchemy.client
   ```

> 重要（互換ポリシー）: protobuf ワイヤ契約の変更を含むリリースでは、**サーバーとデスクトップクライアントを同時更新**してください。片側のみ更新した構成は非サポートです。

接続先やルームを変更する場合:
   ```bash
   mix alchemy.client --connect tcp/127.0.0.1:7447 --room main
   ```

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
| クリーン | `elixir -S mix alchemy.clean` | 依存関係・ビルド成果物を削除 |
| セットアップ | `elixir -S mix alchemy.setup` | deps.get + compile |
| フォーマット | `elixir -S mix alchemy.format` | Elixir + Rust 同時フォーマット |
| テスト | `elixir -S mix alchemy.test` | Elixir + Rust 同時テスト |
| ビルド | `elixir -S mix alchemy.build` | VRAlchemy クライアントをビルド |
| CI 相当 | `elixir -S mix alchemy.ci` | ローカル CI チェック |
| Credo | `elixir -S mix alchemy.credo` | Elixir 静的解析 |
| Protobuf 生成 | `elixir -S mix alchemy.gen.proto` | `.proto` から Elixir/Rust 生成（公式エントリ。詳細は `workspace/2_todo/protobuf-full-automation-procedure.md`） |

CI の詳細は [docs/warranty/ci.md](./docs/warranty/ci.md) を参照。

## Protobuf（`.proto`）

スキーマの単一ソースはリポジトリ直下の **`proto/*.proto`**。生成物の更新は **`mix alchemy.gen.proto`** を公式エントリとする（実装は段階的に同タスクへ集約）。ツール導入、`build.rs`、CI、生成物の置き方の詳細は、作業用ツリー `workspace/2_todo/protobuf-full-automation-procedure.md` に書く。

- 公開向けの短い概要: [docs/architecture/protobuf-migration.md](./docs/architecture/protobuf-migration.md)
- ワイヤ形式とレガシー ETF: [docs/architecture/erlang-term-schema.md](./docs/architecture/erlang-term-schema.md)

## クライアントビルド

```bash
elixir -S mix alchemy.build              # デフォルト: debug ビルド
elixir -S mix alchemy.build --release    # リリースビルド
```

## 関連ドキュメント

- [Protobuf 移行（概要）](./docs/architecture/protobuf-migration.md)
- [ビジョンと設計思想](./docs/vision.md)
- クライアント・サーバー分離・ランチャー設計: [README.md](./README.md) の Architecture 付近を参照（作業用ツリー配下の文書へのリンクは張らない）
- [クライアント exe のビルド・クロスコンパイル](./docs/cross-compile.md)
