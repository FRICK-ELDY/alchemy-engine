# 実施計画: `alchemy-engine` スーパープロジェクト化（world-server / client + protocol）

> **置き場**: `.workspace/2_todo`（段階 A 完了済み。段階 B 着手可。完了後に `3_done` へ）  
> **作成日**: 2026-09-22  
> **目的**: [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) を **ドキュメント／計画の正本を持つスーパープロジェクト**にし、実行コードを submodule で束ねる。  
> **protocol 方針（決定・改訂）**:  
> - 子の **`3rdparty/alchemy-protocol` は廃止**する。  
> - 子は **生成物をコミット**してビルド・実行する（ランタイムは `.proto` 不要）。  
> - 親は **推奨セットの並列ピン**（`world-server` / 将来 `client` / 任意で閲覧・再生成用の `alchemy-protocol`）。  
> - 子のビルドは **親パス（`PROTO_ROOT=../alchemy-protocol`）を見ない**。再生成時だけ独立リポまたは親に並べた protocol を **明示的に**渡す。  
> **残すもの（親本体）**: **`.workspace`**、実行子の gitlink、任意で protocol の作業用 gitlink、`bin/*.bat`。  
> **関連**: [protocol-repo-extraction-procedure.md](protocol-repo-extraction-procedure.md)、[alchemy-server-client-bridge-repos-plan.md](alchemy-server-client-bridge-repos-plan.md)。bridge は任意。

---

## 1. 要約と完了条件

### 1.1 依存の向き（保証の原則）

```text
親 alchemy-engine     … 子（と任意で protocol）の推奨リビジョン組み合わせをピンしてよい
子 world-server/client … 親を知ってはいけない。ビルドはコミット済み生成物に依存
protocol リポ         … ワイヤ契約の SSoT（.proto）。再生成の入力
```

| 層 | 保証すること | 保証しないこと |
|:---|:---|:---|
| **親** | `.workspace`。束ねている **world-server / client（＋任意 protocol）のリビジョン**。推奨互換表 | 子が親ディレクトリ構造を前提にビルドすること |
| **各子** | **コミットされた生成物**と、それが由来する **protocol タグの明示**（文書／コメント／CI） | 日常ビルドで `3rdparty` や親相対 `PROTO_ROOT` が存在すること |
| **protocol** | `.proto` の形 | エンジンのフォルダレイアウト |

### 1.2 最終ゴール（レイアウト）

```text
alchemy-engine/                            # スーパープロジェクト
├── .workspace/                            # 計画・推奨互換表（protocol-lock 含む）
├── .gitmodules
├── bin/                                   # 暫定: world-server 向け bat ラッパ
├── protocol/                              # submodule（再生成・閲覧用。ビルド契約ではない）
├── world-server/                          # submodule → alchemy-world-server
│   ├── apps/.../proto/generated/*.pb.ex   # Elixir 生成物（コミット）
│   └── rust/...                           # Rust は生成物コミット or 同等（段階 B で 3rdparty 廃止）
└── alchemy-client/                        # 段階 C
```

| リポジトリ | 役割 |
|:---|:---|
| **`alchemy-engine`** | メタの玄関。推奨セット並列ピン。 |
| **`alchemy-protocol`** | ワイヤ契約の SSoT。 |
| **`alchemy-world-server`** | サーバー実行体。生成物を保持。`3rdparty` なし。 |
| **`alchemy-client`** | クライアント実行体（段階 C）。同様。 |

### 1.3 段階ゴール

| 段階 | 内容 | 状態 |
|:---|:---|:---|
| **A** | 親＋`world-server` submodule。コード移管（H1）。`bin/*.bat` | **完了** |
| **B** | `3rdparty` 廃止。生成物コミット運用。protocol-lock を子ピン視点へ。親に任意で protocol 並列ピン | **次** |
| **C** | `alchemy-client` 抽出。同様に生成物運用。推奨セットに client を追加 | 未着手 |

### 1.4 完了条件

#### 段階 A（完了）

- [x] `alchemy-world-server` が存在し、親が `world-server/` submodule でピンする。  
- [x] 親に `.workspace` と clone／`bin` 手順がある。  

#### 段階 B

- [ ] `world-server` から **`3rdparty/alchemy-protocol` を削除**し、通常の `mix` / `cargo` ビルドが **proto ツリーなしで通る**。  
- [ ] Elixir 生成物は引き続きリポにコミット（現状 `apps/network/.../generated/*.pb.ex`）。  
- [ ] Rust も **ビルド時に 3rdparty を要求しない**（生成 Rust をコミットする、または同等の方式）。  
- [ ] 再生成は `mix alchemy.gen.proto` が **`PROTO_ROOT`＝独立 clone／親の任意 submodule 等を明示指定**したときだけ（既定パスに 3rdparty を置かない）。  
- [ ] [protocol-lock.md](../0_docs/protocol-lock.md) が「推奨タグ＋各子の生成物の見方」を記述。追従は **同一 PR で Elixir／Rust 生成物を更新**。  
- [ ] 親に `alchemy-protocol` を並列ピンする場合、README で **ビルド非依存**と明記。  

#### 段階 C 以降

- [ ] client 抽出後も同じ生成物運用。  
- [ ] 本計画が `3_done` へ。  

---

## 2. 前提・非目標

### 2.1 前提（現状調査メモ）

- Elixir: `apps/network/lib/network/proto/generated/**/*.pb.ex` は **既にコミット済み**。  
- Rust: `build.rs` + `include!(OUT_DIR/...)` で **ビルド時に `.proto` から生成**しており、現状デフォルトが `3rdparty/alchemy-protocol/proto`。ここが段階 B の主作業。  
- `3rdparty/alchemy-protocol` は素のツリー（正式 submodule ですらない）状態から移管された。  

### 2.2 非目標

- 子が親レイアウトを必須とするビルド。  
- bridge 別リポの必須化。  
- 段階 B での client 抽出（それは C）。  

### 2.3 再生成の入力の渡し方（子は親を「知らない」）

| 方式 | 内容 |
|:---|:---|
| **推奨** | 再生成する開発者／CI が `PROTO_ROOT` に **alchemy-protocol の `proto/` 絶対パスまたは明示パス**を渡す。親に並列 checkout がある場合も、**人が `PROTO_ROOT` をセットする**（コードに `../alchemy-protocol` を焼かない）。 |
| 禁止 | ソースに `PROTO_ROOT` 未設定時のフォールバックとして親相対パスをハードコードすること。 |

---

## 3. 段階 B の実施ステップ

### B0 — 文書合意

- [x] `3rdparty` 廃止＋生成物コミット＋親の推奨セット並列ピン、で合意。  

### B1 — world-server: Rust を proto 非依存の日常ビルドに（本体）

候補（いずれか一つに決める）:

| 案 | 内容 | 長所 | 短所 |
|:---|:---|:---|:---|
| **R1（推奨寄り）** | `prost` 生成結果を `src/` 配下等にコミットし、`build.rs` の proto 必須を外す（再生成時だけ gen） | clone が単純。CI が proto／protoc 不要 | 生成物の差分が大きくなりがち |
| **R2** | ビルド時のみ git 依存／一時取得で proto を取る | リポが軽い | オフライン・再現性・ネットワーク依存 |

Elixir は現状どおり生成物コミットでよい。`mix alchemy.gen.proto` の既定パスを 3rdparty から外し、**`PROTO_ROOT` 必須**（または引数）にする。

### B2 — `3rdparty/alchemy-protocol` 削除

- [ ] ツリー削除、README／CI／`build.rs`／`alchemy.gen.proto` の参照更新。  
- [ ] 子単体 clone で `mix compile` / 主要 `cargo build -p network` が通ることを確認。  

### B3 — 親: protocol-lock と任意並列ピン

- [ ] [protocol-lock.md](../0_docs/protocol-lock.md) を改訂（推奨タグ、子での確認方法、追従手順）。  
- [ ] 任意: 親に `alchemy-protocol` submodule を追加（再生成用）。ビルド必須にしない。  
- [ ] 親 README に「日常ビルドは world-server の生成物のみ」と明記。  

### B4 — 運用規約

- [ ] protocol タグ上げ → **world-server で Elixir＋Rust 生成物を同一 PR**で更新 → 親の submodule ピン／推奨表を必要なら更新。  
- [ ] （段階 C 後）client も同じタグから再生成し、統合前にタグ一致を確認。  

---

## 4. 段階 A で実施済み（参考）

- H1 で `alchemy-world-server` へ履歴付き移管。  
- 親からコード削除、`world-server/` submodule、README、`bin/*.bat`。  

---

## 5. 段階 C（概要・変更なしの趣旨）

- `rust/client` 等を `alchemy-client` へ。生成物運用を踏襲。  
- 親の並列ピンに client を追加。  

---

## 6. 他計画・bridge

bridge 別リポは任意のまま。本方針（生成物コミット）とも直交。

---

## 7. clone / 開発者体験（段階 B 後の目標）

```bash
git clone --recurse-submodules git@github.com:FRICK-ELDY/alchemy-engine.git
cd alchemy-engine
# 日常（proto 不要）
bin\setup.bat          # Windows
# または
cd world-server && mix deps.get && mix compile
```

再生成例（明示）:

```bash
git clone git@github.com:FRICK-ELDY/alchemy-protocol.git /tmp/alchemy-protocol
cd world-server
set PROTO_ROOT=/tmp/alchemy-protocol/proto   # Windows は set / $env:
mix alchemy.gen.proto
# 生成物の diff をレビューしてコミット
```

---

## 8. リスク

| 項目 | 内容 | 緩和 |
|:---|:---|:---|
| Elixir／Rust 生成物のずれ | 別 PR で片方だけ更新 | 同一 PR 規約。任意で CI が protocol タグと照合 |
| Rust 生成物の巨大 diff | prost 出力のコミット | フォーマット固定、不要ファイルを出さない |
| 旧 `PROTO_ROOT` 習慣 | 親相対の焼き込み | コードレビューで禁止。未設定時は明確にエラー |
| 再生成環境 | protoc / protoc-gen-elixir | development.md に限定して記載 |

---

## 9. 関連ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [protocol-lock.md](../0_docs/protocol-lock.md) | 推奨タグ（段階 B で改訂） |
| [protocol-repo-extraction-procedure.md](protocol-repo-extraction-procedure.md) | 契約リポ（取り込みは本計画の生成物運用を優先） |
| world-server `mix alchemy.gen.proto` | 再生成エントリ |

---

## 10. 改訂履歴

| 日付 | 内容 |
|:---|:---|
| 2026-09-22 | 初版〜スーパープロジェクト／H1／子タグ固定案 |
| 2026-09-22 | 子は親を見ない・3rdparty／deps タグ固定を決定 |
| 2026-09-22 | submodule パスを `world-server/` に |
| 2026-09-23 | 段階 A 完了（移管・親 superproject・bin） |
| 2026-09-23 | **改訂**: `3rdparty` 廃止＋**生成物コミット運用**＋親は**推奨セット並列ピン**（ビルドは親非依存） |
| 2026-09-23 | 親に submodule **`protocol/`**（alchemy-protocol @ `v0.1.2`）を追加。`proto/` は world-server の `3rdparty` と一致を確認 |
