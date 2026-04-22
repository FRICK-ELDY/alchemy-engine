# プロトコル周りの別リポジトリ化 — 実施手順書

> **置き場**: `workspace/2_todo`（着手前の実施手順）  
> **作成日**: 2026-04-22  
> **目的**: ワイヤ契約（`.proto`、Zenoh／UDP 等のペイロード仕様、契約テスト）を **alchemy-engine 本体から分離したリポジトリ**に移し、Elixir チームと Rust チームが **同じソースオブトゥルース**を参照できるようにする。将来の **Cap’n Proto 等への差し替え**は本手順のスコープ外とし、境界の置き方だけ後続で可能になるよう記載する。

---

## 1. 要約と完了条件

### 1.1 ゴール

| 項目 | 内容 |
|:---|:---|
| **SSoT** | アプリ間ワイヤの `.proto` と、それに紐づく **人間可読仕様**（キー表式・ペイロード対応表など）を **プロトコル用リポジトリ**に集約する。 |
| **alchemy-engine** | 上記を **バージョン付きで取り込み**、`mix alchemy.gen.proto` / `prost-build` が **取り込み先の `proto/`** を参照する。ルートの `proto/` は削除または薄いラッパにする。 |
| **CI** | プロトコルリポ単体で **契約検証**（`protoc` での検証、既存の encode/decode 往復テストの移管または二重実行）が通る。エンジン側 CI は **ロックされたリビジョン**のプロトと整合することを確認する。 |

**補足（二層の SSoT）**: 上表の **SSoT** は **アプリ間ワイヤの契約**に限る。ゲーム状態・ルールの **ドメイン SSoT** は alchemy-engine 側の **Elixir**（[docs/architecture/overview.md](../../docs/architecture/overview.md#設計思想)）。

### 1.2 完了条件（Definition of Done）

- [ ] GitHub 上に **プロトコル専用リポジトリ**が存在し、ライセンス・README・変更履歴がある。  
- [ ] `alchemy-engine` が **Git の tag または commit SHA** でプロトを固定し、`mix test` / 主要な `cargo build` が通る。  
- [ ] `docs/architecture/` および `docs/policy-as-code/` の **proto パス参照**が新リポまたはバージョン表記に更新されている。  
- [ ] 旧パス（ルート `proto/`）を参照するドキュメント・スクリプト・CI が残っていない、または意図した互換ラッパのみである。  
- [ ] **後任者向け**: プロトを変更する PR のレビュー担当と **破壊的変更の扱い**が README または CONTRIBUTING に書かれている。

---

## 2. スコープ — 移すもの／残すもの

### 2.1 新リポジトリへ移す（推奨）

| 種別 | 現状（alchemy-engine） | 備考 |
|:---|:---|:---|
| **スキーマ** | `proto/**/*.proto`（エントリは `render_frame.proto` およびルート直下の各 `.proto`） | `import` ツリーごと移動。パッケージ名・フィールド番号は変えない。 |
| **ワイヤ仕様ドキュメント** | `docs/architecture/zenoh-protocol-spec.md`、`docs/architecture/network-protocol-current.md` のうち **契約記述中心の節** | 長い歴史節はエンジン側に残し、リンクで分離してもよい。 |
| **契約テスト** | `apps/network/test/network/proto/protobuf_contract_test.exs` 等、**ワイヤのみ**に依存するテスト | エンジン固有のモックに依存するものはエンジン側に残す。 |
| **方針ドキュメント（任意）** | `docs/policy-as-code/elixir_zenoh.md` の protobuf 方針節の **要約＋リンク** | 全文移管するとエンジン固有ポリシーと混ざるため、**二重管理を避ける**なら要約のみ新リポへ。 |

### 2.2 alchemy-engine に残す（境界）

| 種別 | 理由 |
|:---|:---|
| **`Content.FrameEncoder` 等** | DrawCommand 等の **ドメイン型 → protobuf メッセージ**のマッピングはゲームエンジンの責務。生成モジュール（`Alchemy.Render.*`）を**呼ぶ側**はエンジンに残す。 |
| **`Network.ZenohBridge`、UDP サーバ、トピック名の定数** | トランスポートとルーティングはデプロイ・OTP と結びつく。ただし **キー文字列とペイロード形式の表**はプロトコルリポへ寄せられる。**別途**、実装の多くを **`alchemy-server-bridge` / `alchemy-client-bridge`** リポへ寄せる計画は [alchemy-server-client-bridge-repos-plan.md](./alchemy-server-client-bridge-repos-plan.md) を参照（本手順の §2.2 は「当面エンジンに残る境界」の記述として読み替え可）。 |
| **`rust/client/render_frame_proto` のデコードロジック** | ワイヤ解釈は共有、**描画パイプラインへの変換**はクライアント。必要なら後続で「プロト用 Rust クレート」に切り出す別タスクとする。 |
| **Phoenix Channel の JSON イベント** | ブラウザ経路が別契約なら、**フェーズ 2** で「Web 用契約」をプロトコルリポに含めるか別ドキュメントにするか決める（§6.1）。 |

### 2.3 境界の原則（後の Cap’n Proto 差し替えに効く）

- **ワイヤの意味**（バイト列・フィールド番号・キー表式）はプロトコルリポ。  
- **意味の実装**（エンコードのための組み立て、デコード後の ECS／描画への載せ替え）はエンジン／クライアント。  
- 将来 XR で Cap’n を足す場合も、**同じリポに「device 用スキーマ」ディレクトリを増やす**か、別リポにするかを **レイヤー図で先に決める**（本手順では決定のみ記録でよい）。

---

## 3. 新リポジトリの推奨レイアウト

リポジトリ名は組織の命名規則に合わせる（例: `alchemy-protocol`, `frick-alchemy-wire`）。

```text
<protocol-repo>/
  README.md                 # 利用方法（エンジンからの取り込み）、バージョン方針
  CHANGELOG.md              # スキーマの破壊的変更はここに必ず記載
  LICENSE                   # エンジン本体と同一または互換ライセンスを推奨
  CONTRIBUTING.md           # .proto のフィールド番号ルール、レビュー必須者
  proto/                    # 現行 alchemy-engine の proto/ と同一ツリー推奨
    render_frame.proto
    render_frame/
    input_events.proto
    ...
  docs/
    wire-overview.md        # zenoh-protocol-spec 相当の要約（移設または新撰）
  .github/workflows/
    proto-lint.yml          # buf 等は任意。最低限 protoc --descriptor_set_out 等で検証
```

- **パッケージ公開（Hex / crates.io）**は初回必須としない。まず **Git + tag** で十分なことが多い。  
- 将来 **生成物だけ**を配布する場合は [protobuf-full-automation-procedure.md](../7_done/protobuf-full-automation-procedure.md) 完了後に再検討する。

---

## 4. バージョンと互換ポリシー（先に決める）

| 決定事項 | 推奨 |
|:---|:---|
| **タグ付け** | セマンティックバージョン `vMAJOR.MINOR.PATCH` を **プロトコルリポのみ**で打つ（エンジンのリリース番号と独立）。 |
| **破壊的変更** | `MAJOR` を上げる。エンジンは `mix.lock` 相当として **Cargo / Mix で rev 固定**し、意図的に追従する。 |
| **後方互換** | proto3 のフィールド追加のみを同一 `MAJOR` 内の既定とする。`reserved` の運用ルールを CONTRIBUTING に書く。 |
| **エンジン側の追従** | 「プロト `vX` に上げる」PRは **Elixir と Rust の生成物・契約テスト**を同一 PR で更新する方針を README に明記する。 |

---

## 5. フェーズ別実施手順

### フェーズ 0 — 棚卸しと合意（1〜2 日）

1. `proto/` 以下の全ファイルと `import` 依存を一覧化する。  
2. `grep -r "proto/"`（または IDE 全体検索）で **ドキュメント・CI・build.rs・Mix タスク**の参照箇所を洗い出す。  
3. 上記 §2 の「移す／残す」をレビューし、**Phoenix JSON** や **UDP 生パケット**を第何フェーズで扱うか決める（§6.1）。  
4. 新リポの **GitHub 権限**（誰が merge できるか）を決める。

### フェーズ 1 — プロトコルリポジトリ新設（0.5〜1 日）

1. 空リポジトリを作成する。  
2. `proto/` ツリーを **履歴付きでコピー**する（`git subtree split` や単純コピー＋初回コミット。組織方針に合わせる）。  
3. `README.md` に **取り込み例**（§7）を書く。  
4. `CHANGELOG.md` に「初回: alchemy-engine の移設元コミット」を記載する（短縮ハッシュで可）。  
5. 任意: `protoc -I proto --descriptor_set_out=/dev/null` 相当で **全 `.proto` がコンパイル可能**であることを CI で確認する。

### フェーズ 2 — alchemy-engine からの取り込み経路（1〜2 日）

次のいずれか **一つに統一**する（複数併用は運用が壊れやすい）。

| 方式 | 長所 | 短所 |
|:---|:---|:---|
| **A. Git submodule** | パスが安定、`deps/../proto` と同様に参照しやすい | clone 手順の教育が必要 |
| **B. Mix / Cargo の `git` 依存 + sparse** | submodule なし | 初回 clone 先のパス把握が必要（Mix は `deps/` 下に展開） |

**推奨（実装が単純な順）**: チームが submodule に慣れているなら **A**。慣れていないなら **B** で `sparse: "proto"` を指定し、展開先を `PROTO_ROOT` 環境変数や Mix タスク内で解決する。

**方式 A と B でパスが異なる**: submodule は多くの場合 `3rdparty/alchemy-protocol/proto/` に `.proto` が並ぶ。`sparse: "proto"` の Mix 依存では、依存のルートが **上流リポの `proto/` ディレクトリの内容そのもの**になる（§7.1）。Rust の `build.rs` はクレートごとに `CARGO_MANIFEST_DIR` からリポジトリルートまでの `..` の段数が違うため、**相対パスをハードコードだけで統一するのは事故りやすい**。

実装タスク（エンジン側）:

1. ルートの `proto/` を **削除**し、代わりに submodule 用ディレクトリ（例: `3rdparty/alchemy-protocol`）を置く **または** Mix の git 依存（`sparse: "proto"` 等）で取得する。取得先の実パスは方式 A/B で異なる（§7）。  
2. **`Mix.Tasks.Alchemy.Gen.Proto`**（`apps/core/lib/mix/tasks/alchemy.gen.proto.ex`）の `proto_dir` を、**PROTO_ROOT**（環境変数または Mix が解決した絶対パス）に解決するように変更する。  
3. **Rust** の各 `build.rs`（`rust/client/render_frame_proto/build.rs`、`rust/client/network/build.rs` 等）の `proto_root` は、**標準手順として `std::env::var("PROTO_ROOT")` を最優先**し、未設定時のみ `CARGO_MANIFEST_DIR` からの相対パスにフォールバックする。CI・ローカルとも、`PROTO_ROOT` を明示すれば **方式 A/B の差とクレート深度の差を吸収**できる。  
   - フォールバック例（現行レイアウト・**submodule が `3rdparty/alchemy-protocol/proto/` の場合**）: `rust/client/network` や `rust/client/render_frame_proto` からはリポジトリルートまで `../../../` のため、デフォルトは `../../../3rdparty/alchemy-protocol/proto` のように **3 段上がる**（`../../3rdparty/...` は **1 段足りない**）。`rust/nif` のように `rust/` 直下のクレートでは `../../3rdparty/...` で足りるなど、**クレートごとに検証すること**。  
4. ルート `mix.exs` に **開発用オプション**（`config :alchemy, :proto_path` 等）を置く場合は、**デフォルトは submodule／deps パス**にし、ローカルオーバーライドのみ env で上書き可能にする。`cargo` 実行時に `PROTO_ROOT` を渡す方法（ドキュメント化・`cargo build` 前の export 等）を `development.md` に書く。

### フェーズ 3 — 生成物とテスト（1〜2 日）

1. `mix alchemy.gen.proto` を実行し、`apps/network/lib/network/proto/generated/*.pb.ex` が **従来と同一か diff 最小**であることを確認する（パス変更のみならバイト同一が理想）。  
2. `cargo build -p render_frame_proto -p network`（および NIF が proto を参照する場合は `-p nif`）を実行する。  
3. `mix test apps/network/test/network/proto/` および既存の Zenoh 関連テストを実行する。  
4. 契約テストをプロトコルリポに **コピーした場合**は、そちらでも最小限の CI（例: Elixir だけの小さな matrix）を回すか、**エンジン CI から `PROTO_VERSION` を指定してチェックアウト**する二段構えにする。

### フェーズ 4 — ドキュメントとポリシー追随（0.5〜1 日）

1. `docs/architecture/protobuf-migration.md`、`zenoh-protocol-spec.md`、`network-protocol-current.md` 内の **`../../proto/` リンク**を、新リポの **タグ付き URL**（例: `https://github.com/ORG/alchemy-protocol/blob/v0.1.0/proto/render_frame.proto`）に更新する。  
2. `workspace/7_done/protobuf-full-automation-procedure.md` の「`proto/*.proto` はリポジトリルート」という記述を、**PROTO_ROOT** 前提に更新する（別 PR 可）。  
3. `development.md` に **初回 clone 後に submodule 初期化**または **deps 取得**の手順を追記する。

### フェーズ 5 — クリーンアップとロック（0.5 日）

1. ルートに **`PROTO_VERSION` または `PROTO_GIT_REV`** を記録するファイル（例: `.proto-version` または `docs/protocol-lock.md`）を置き、**意図しない追従**を防ぐ。  
2. Dependabot 等で submodule を上げる運用にするか、**月次で人が rev を更新**するか決める。  
3. 古い `proto/` へのリンクを Web から辿れるように、alchemy-engine の README に **1 行の移設告知**を入れる（任意）。

---

## 6. 補足判断（実施前に決めるとよいこと）

### 6.1 UDP パケット形式・Phoenix JSON

- **`Network.UDP.Protocol`** の固定ヘッダ＋種別バイトは **現状エンジン内のモジュールドキュメントが仕様**である。これをプロトコルリポの `docs/udp-envelope.md` に移すか、**Zenoh 一本化後に廃止予定**なら移管を遅延してよい。  
- **Phoenix Channel** の JSON イベントは **別契約**である。OSS でブラウザクライアントを想定するなら、**OpenAPI または JSON Schema** をプロトコルリポに追加するフェーズを別タスクに切るとよい。

### 6.2 生成コードの置き場

- **現行方針**: Elixir の生成物は `apps/network/lib/network/proto/generated/` にコミットする流れ（`mix alchemy.gen.proto`）。プロトコルリポに **生成 `.ex` をコミットしない**方が、生成器バージョンの食い違いが減る。  
- 将来、生成物をプロトコルリポで配布する場合は **Hex パッケージ化**の設計が必要（§8 不足構想参照）。

### 6.3 セキュリティ・サプライチェーン

- プロトコルリポの **tag 改ざん**に依存しないよう、エンジンの lock ファイルに **commit SHA** を明示するか、GitHub の **verified tag** 運用を検討する。  
- 外部コントリビュータ向けに、**proto 変更はメンテナ承認必須**とする branch protection を有効にする。

---

## 7. 取り込み例（参考スニペット）

実際の URL・rev は置き換えること。

### 7.1 Mix（git + sparse の例）

```elixir
# ルート mix.exs の deps（例）。実際の app 名・URL は組織に合わせる。
{:alchemy_protocol_files,
  git: "https://github.com/ORG/alchemy-protocol.git",
  sparse: "proto",
  ref: "v0.1.0",
  compile: false,
  app: false}
```

`sparse: "proto"` を指定すると、Mix は上流リポジトリの **`proto/` サブツリーだけ**を依存先に展開し、**依存のルートディレクトリがすでに `.proto` の親**になる（`deps/alchemy_protocol_files/render_frame.proto` のように並ぶ）。そのため `Mix.Tasks.Alchemy.Gen.Proto` では `Path.join(Mix.Project.deps_path(), "alchemy_protocol_files")` を **PROTO_ROOT として解決**し、末尾に **`/proto` を二重に付けない**こと。**アプリ名（依存キー）は実装時に衝突しない名前にする**。

### 7.2 Git submodule の例

```bash
git submodule add https://github.com/ORG/alchemy-protocol.git 3rdparty/alchemy-protocol
# proto は 3rdparty/alchemy-protocol/proto/
```

この場合の PROTO_ROOT は **`3rdparty/alchemy-protocol/proto`（リポジトリルートからの相対）** である。`build.rs` ではフェーズ 2 の実装タスクどおり **`PROTO_ROOT` 環境変数を優先**し、未設定時のみ例として `rust/client/network` から `../../../3rdparty/alchemy-protocol/proto` のように **クレート位置に合わせた相対**で指定する（段数は必ず実パスで検証する）。

---

## 8. 不足しがちな構想・指摘（チェックリスト）

実施手順だけでは後から詰まりやすい点を列挙する。**本書の「完了条件」に取り込むか、別イシューに切り出すこと。**

| # | 項目 | 指摘内容 |
|:---|:---|:---|
| 1 | **Buf / Schema Registry** | チームが増えたら `buf lint` / `buf breaking` で **互換破壊を機械検出**すると安全。初回から必須にしなくてよいが、**導入判断と時期**をメモしておく。 |
| 2 | **多言語生成の単一パイプライン** | [protobuf-full-automation-procedure.md](../7_done/protobuf-full-automation-procedure.md) が未完のうちは、**二リポでも「生成コマンドはエンジン側に一本」**のままでよい。自動化完了後に **プロトリポで生成して配布**へ移行するか再評価する。 |
| 3 | **契約テストの単一実行場所** | テストを両リポに複製すると二重メンテになる。**推奨**: 厳密な往復はプロトコルリポ（最小 Elixir/Rust ワークスペース）、エンジンは **統合テスト**に留める。 |
| 4 | **Rust の prost-build** | `render_frame_proto` / `network` 等、**`build.rs` で `proto/` を参照する全クレート**を `grep`/Cargo で洗い出し、フェーズ 2 でパスを漏れなく更新する（現行の `nif` は protobuf を参照しないが、将来復活時に同様）。 |
| 5 | **Windows 開発者** | `PROTOC` 環境変数と `PATH`（`protoc-gen-elixir`）の手順を **development.md に明記**。submodule の初期化も Windows で同じコマンドか確認する。`PROTO_ROOT` を **Cargo と Mix の両方**で揃える（sparse 時は `deps/<name>/` がルートで `/proto` 二重付与に注意）。 |
| 6 | **OSS とライセンス** | プロトコルリポの LICENSE は **エンジンと互換**にし、外部が **単体で fork しやすい**ようにする。 |
| 7 | **「プロトコル」と「ゲームデータ」** | ワールドの意味論までプロトリポに寄せすぎると境界が曖昧になる。**ワイヤに出るメッセージのみ**を原則とする。 |
| 8 | **Cap’n Proto 共存** | 将来 XR 用に別 IDL を足す場合、**同一リポの `schemas/capnp/`** にするか **別リポ**にするかを **レイヤー図で固定**しないと、また「どこが SSoT か」が分断する。 |
| 9 | **リリースノートの二重記載** | フィールド追加がユーザー向けリリースノートに影響する場合、**エンジン RELEASE とプロト CHANGELOG**の役割分担を決める。 |
| 10 | **エラー文言・理由コード** | ワイヤ上の `reason` 文字列を増やす場合、**安定した機械可読コード**（列挙）と人間向け文字列を分ける設計を検討（国際化・ログ解析に効く）。 |

---

## 9. 関連ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [client-server-separation-procedure.md](../7_done/client-server-separation-procedure.md) | クライアント／サーバー分離の実施済み手順 |
| [protobuf-full-automation-procedure.md](../7_done/protobuf-full-automation-procedure.md) | `mix alchemy.gen.proto` と生成物自動化の狙い |
| [zenoh-protocol-spec.md](../../docs/architecture/zenoh-protocol-spec.md) | Zenoh 上の protobuf 契約（移設候補） |
| [network-protocol-current.md](../../docs/architecture/network-protocol-current.md) | 現行ネットワーク経路の説明 |

---

## 10. 改訂履歴

| 日付 | 内容 |
|:---|:---|
| 2026-04-22 | 初版（`workspace/2_todo` に手順書として作成） |
| 2026-04-22 | レビュー反映: `PROTO_ROOT` を `build.rs` / Mix の標準解決に明記。`sparse: "proto"` 時は `deps/<name>/` がルートで `/proto` を二重に付けない。方式 A/B とクレート深度による相対パス差を追記。 |
