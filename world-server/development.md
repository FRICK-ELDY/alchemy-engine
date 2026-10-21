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

1. リポジトリをクローンします（単体でも、親 [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) の `world-server/` submodule でも可）。
   ```bash
   git clone git@github.com:FRICK-ELDY/alchemy-world-server.git
   cd alchemy-world-server
   ```

2. 開発環境のセットアップを実行します（Rust の prost 生成は **`PROTOCOL_PIN` に従い初回 git fetch**。Elixir の `*.pb.ex` はリポにコミット済み）。
   ```bash
   mix deps.get
   mix alchemy.setup
   ```

### Rust NIF（`rust/nif`）

`mix compile` のたびに Rustler が **`rust/nif` を release ビルド**し、`Core.NifBridge` にリンクします。現行 NIF は **Formula 用 `run_formula_bytecode` のみ**（ゲーム物理・ECS 用 NIF は撤去済み）。ワークスペース単体の検証例:

```bash
cd rust && cargo build -p nif
```

古いビルドキャッシュ `native/target/` が残っている場合は削除して問題ありません（現行は `rust/target/` を使用）。

## 起動方法

### サーバー単体起動

```bash
mix alchemy.server
```

または `mix run --no-halt`

`mix run` 単体ではウィンドウは開かず、サーバーのみ起動します。ゲームをプレイするには zenohd と [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client)（VRAlchemy）を別途起動してください。

### ランチャー（システムトレイ）

zenohd / HL-Server / Client をトレイメニューから管理します（Phase 0–6 対応）。

```bash
cd ../alchemy-launcher
cargo run
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

`alchemy-launcher` リポジトリのランチャーを使用して zenohd、サーバー、クライアントを管理します。

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

3. ターミナル 3: デスクトップクライアントを起動（[alchemy-client](https://github.com/FRICK-ELDY/alchemy-client)）
   ```bash
   cd ../alchemy-client   # 親スーパープロジェクトなら cd ../client
   cargo run -p app -- --connect tcp/127.0.0.1:7447 --room main
   ```

> 重要（互換ポリシー）: protobuf ワイヤ契約の変更を含むリリースでは、**サーバーとデスクトップクライアントを同時更新**してください。片側のみ更新した構成は非サポートです。

接続先やルームを変更する場合は上記の `--connect` / `--room` を変えてください。

### リモート Client（Windows ホスト + Mac Client）

Windows をホスト（Router / Server / Client）、Mac を Client のみにする場合。iPhone テザリングでも、両機が同じホットスポットに入っていれば同じ手順です。

1. **Windows（ホスト）** — 3 ターミナル
   ```bash
   mix alchemy.router
   mix alchemy.server
   # 別 cwd で alchemy-client:
   cargo run -p app -- --connect tcp/127.0.0.1:7447 --room main
   ```
   Windows では `mix alchemy.router` が TCP/UDP の `0.0.0.0:7447` と `[::]:7447` で待ち受ける（Unix は `[::]` のみで IPv4 もカバー）。Windows のテザリング側 IPv4 を控える（例: `ipconfig` で `172.20.10.x`）。初回は TCP/UDP 7447 の受信をファイアウォールで許可する。

2. **Mac（Client のみ）** — 同じコンテンツ世代の alchemy-client で:
   ```bash
   cargo run -p app -- --connect udp/<WINDOWS_IP>:7447 --room main
   ```
   `<WINDOWS_IP>` はホストのテザリング IPv4。`127.0.0.1` では Mac から Windows に届かない。リモートは **UDP** を使う（TCP だとテザリングで遅延が蓄積しうる）。`tcp/` を指定しても Client が loopback 以外なら UDP に読み替える。

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
| ビルド | `elixir -S mix alchemy.build` | （移管）alchemy-client へ案内 |
| CI 相当 | `elixir -S mix alchemy.ci` | ローカル CI チェック |
| Credo | `elixir -S mix alchemy.credo` | Elixir 静的解析 |
| Protobuf 生成 | `elixir -S mix alchemy.gen.proto` | `.proto` から Elixir 生成（Rust は alchemy-client） |

CI の詳細は [.workspace/0_docs/warranty/ci.md](.workspace/0_docs/warranty/ci.md) を参照。

<a id="protobuf-proto"></a>

## Protobuf（`.proto`）

**ワイヤ契約の SSoT** は [FRICK-ELDY/alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol)。本リポでは **`PROTOCOL_PIN`** でタグ／SHA を固定し、再生成時は **`.proto-cache/` へ git fetch（R2）**します。Elixir の `apps/network/.../generated/*.pb.ex` はリポにコミット済みです。

- 上書き: 環境変数 **`PROTO_ROOT`**（親スーパープロジェクトなら例: `../protocol/proto` を**明示**）
- 再生成: **`mix alchemy.gen.proto`**（Elixir 生成物のみ）
- Rust クライアントの prost: [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client)（同一 `PROTOCOL_PIN`）
- 旧 **`3rdparty/alchemy-protocol` は廃止**
- UDP／Phoenix JSON など別形式は overview の表を参照

## クライアントビルド

クライアントは別リポです:

```bash
cd ../alchemy-client   # または親の client/
cargo build -p app
cargo build -p app --release
```

## 関連ドキュメント

- [ラボ開発環境（ネットワーク構成図）](.workspace/0_docs/development/lab-environment.md)
- [Protobuf 移行（概要）](.workspace/0_docs/architecture/protobuf-migration.md)
- [ビジョンと設計思想](.workspace/0_docs/vision.md)
- クライアント・サーバー分離・ランチャー設計: [README.md](README.md) の Architecture 付近を参照（作業用ツリー配下の文書へのリンクは張らない）
- [クライアント exe のビルド・クロスコンパイル](.workspace/0_docs/cross-compile.md)
