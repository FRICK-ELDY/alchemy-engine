# 実施計画: `alchemy-engine` スーパープロジェクト化（world-server / client + protocol）

> **置き場**: `.workspace/2_todo`（段階 A・B 完了。段階 C 実施中／完了後に `3_done` へ）  
> **作成日**: 2026-09-22  
> **目的**: [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) を **ドキュメント／計画の正本を持つスーパープロジェクト**にし、実行コードを submodule で束ねる。  
> **protocol 方針（決定）**:  
> - 子の **`3rdparty/alchemy-protocol` は廃止**（段階 B 完了）。  
> - Elixir は **生成物をコミット**。Rust クライアントは **R2（`PROTOCOL_PIN` + `.proto-cache/`）**。  
> - 親は **推奨セットの並列ピン**（`world-server` / `client` / 閲覧・再生成用 `protocol`）。  
> - 子のビルドは **親パスを見ない**。再生成時だけ `PROTO_ROOT` を明示。  
> **残すもの（親本体）**: **`.workspace`**、実行子の gitlink、`bin/*.bat`。  
> **関連**: [protocol-repo-extraction-procedure.md](protocol-repo-extraction-procedure.md)、[alchemy-server-client-bridge-repos-plan.md](alchemy-server-client-bridge-repos-plan.md)。bridge は任意。

---

## 1. 要約と完了条件

### 1.1 依存の向き（保証の原則）

```text
親 alchemy-engine     … 子（と protocol）の推奨リビジョン組み合わせをピンしてよい
子 world-server/client … 親を知ってはいけない。ビルドはコミット済み生成物 / PROTOCOL_PIN に依存
protocol リポ         … ワイヤ契約の SSoT（.proto）。再生成の入力
```

| 層 | 保証すること | 保証しないこと |
|:---|:---|:---|
| **親** | `.workspace`。束ねている **world-server / client / protocol のリビジョン**。推奨互換表 | 子が親ディレクトリ構造を前提にビルドすること |
| **各子** | **コミットされた生成物**（Elixir）または **PROTOCOL_PIN（R2）**（Rust client） | 日常ビルドで `3rdparty` や親相対 `PROTO_ROOT` が存在すること |
| **protocol** | `.proto` の形 | エンジンのフォルダレイアウト |

### 1.2 最終ゴール（レイアウト）

```text
alchemy-engine/                            # スーパープロジェクト
├── .workspace/                            # 計画・推奨互換表（protocol-lock 含む）
├── .gitmodules
├── bin/                                   # world-server / client 向け bat ラッパ
├── protocol/                              # submodule（再生成・閲覧用。ビルド契約ではない）
├── world-server/                          # submodule → alchemy-world-server（nif + Elixir）
│   └── apps/.../proto/generated/*.pb.ex
└── client/                                # submodule → alchemy-client（Rust VRAlchemy）
```

| リポジトリ | 役割 |
|:---|:---|
| **`alchemy-engine`** | メタの玄関。推奨セット並列ピン。 |
| **`alchemy-protocol`** | ワイヤ契約の SSoT。 |
| **`alchemy-world-server`** | サーバー実行体。Elixir 生成物＋ Rust `nif`。 |
| **`alchemy-client`** | クライアント実行体。`PROTOCOL_PIN` + R2。 |

### 1.3 段階ゴール

| 段階 | 内容 | 状態 |
|:---|:---|:---|
| **A** | 親＋`world-server` submodule。コード移管（H1）。`bin/*.bat` | **完了** |
| **B** | `3rdparty` 廃止。R2 `PROTOCOL_PIN`。親に `protocol/` 並列ピン | **完了** |
| **C** | `alchemy-client` 抽出。親に `client/` 追加。world-server は nif のみ | **実施中** |

### 1.4 完了条件

#### 段階 A（完了）

- [x] `alchemy-world-server` が存在し、親が `world-server/` submodule でピンする。  
- [x] 親に `.workspace` と clone／`bin` 手順がある。  

#### 段階 B（完了）

- [x] `world-server` から **`3rdparty/alchemy-protocol` を削除**。  
- [x] Elixir 生成物はリポにコミット。  
- [x] Rust は **R2（PROTOCOL_PIN）** で proto 取得（3rdparty 不要）。  
- [x] `mix alchemy.gen.proto` は `PROTO_ROOT` または PROTOCOL_PIN。  
- [x] [protocol-lock.md](../0_docs/protocol-lock.md) 改訂。親に `protocol/` submodule。  

#### 段階 C

- [x] [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client) 初回投入（H2 スナップショット）。  
- [ ] world-server から client 削除・nif のみ（[PR #2](https://github.com/FRICK-ELDY/alchemy-world-server/pull/2)）。  
- [ ] 親に `client/` submodule・`bin/client.bat` 更新。  
- [ ] 本計画を `3_done` へ（マージ後）。  

---

## 2. 前提・非目標

### 2.1 前提（現状調査メモ）

- Elixir: `apps/network/lib/network/proto/generated/**/*.pb.ex` はコミット済み。  
- Rust client: `build.rs` + R2 `PROTOCOL_PIN`（段階 B）。段階 C で client リポへ移管。  
- world-server Rust: **`nif` のみ**（段階 C）。  

### 2.2 非目標

- 子が親レイアウトを必須とするビルド。  
- bridge 別リポの必須化。  

### 2.3 再生成の入力の渡し方（子は親を「知らない」）

| 方式 | 内容 |
|:---|:---|
| **推奨** | 再生成する開発者／CI が `PROTO_ROOT` に **alchemy-protocol の `proto/`** を明示。 |
| 禁止 | ソースに親相対パスをハードコードすること。 |

---

## 3. 段階 B（完了・参考）

R2 採用。`PROTOCOL_PIN` + `proto_resolve` + `.proto-cache/`。詳細は world-server PR #1 / 親 `chore/stage-b-*`。

---

## 4. 段階 A で実施済み（参考）

- H1 で `alchemy-world-server` へ履歴付き移管。  
- 親からコード削除、`world-server/` submodule、README、`bin/*.bat`。  

---

## 5. 段階 C（実施内容）

1. **alchemy-client**（空リポ）へ `rust/client/*` + `proto_resolve` + `PROTOCOL_PIN` + `assets/` を投入（ワークスペースをフラット化）。  
2. **world-server**: client／proto_resolve／assets 削除、`mix alchemy.client` 削除、`gen.proto` は Elixir のみ。  
3. **親**: `client/` submodule、`bin/client.bat` → `cargo run -p app`、README／protocol-lock／本計画を更新。  

境界:

| 残す（world-server） | 移す（client） |
|:---|:---|
| Elixir apps、`rust/nif`、`PROTOCOL_PIN`（Elixir 再生成用） | `app` ほか client crates、`proto_resolve`、`assets/` |

---

## 6. 他計画・bridge

bridge 別リポは任意のまま。

---

## 7. clone / 開発者体験（段階 C 後）

```bash
git clone --recurse-submodules git@github.com:FRICK-ELDY/alchemy-engine.git
cd alchemy-engine
bin\deps.get.bat
bin\setup.bat
# 別ターミナル ×3
bin\router.bat
bin\server.bat
bin\client.bat
```

---

## 8. リスク

| 項目 | 内容 | 緩和 |
|:---|:---|:---|
| Elixir／Rust 生成物のずれ | 別 PR で片方だけ更新 | 同一 protocol タグで world-server＋client を更新 |
| 親の submodule ピン順序 | world-server 未マージコミットを親が指す | world-server PR マージ後に親ピンを main へ更新 |
| 旧 `mix alchemy.client` 習慣 | ドキュメント・bin を client に誘導 | |

---

## 9. 関連ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [protocol-lock.md](../0_docs/protocol-lock.md) | 推奨タグ |
| world-server `mix alchemy.gen.proto` | Elixir 再生成 |
| alchemy-client `PROTOCOL_PIN` | Rust R2 |

---

## 10. 改訂履歴

| 日付 | 内容 |
|:---|:---|
| 2026-09-22 | 初版〜スーパープロジェクト／H1／子タグ固定案 |
| 2026-09-22 | 子は親を見ない・3rdparty／deps タグ固定を決定 |
| 2026-09-22 | submodule パスを `world-server/` に |
| 2026-09-23 | 段階 A 完了（移管・親 superproject・bin） |
| 2026-09-23 | **改訂**: `3rdparty` 廃止＋**生成物コミット／R2**＋親は**推奨セット並列ピン** |
| 2026-09-23 | 親に submodule **`protocol/`**（alchemy-protocol @ `v0.1.2`） |
| 2026-09-23 | 段階 B 完了（R2）。段階 C: alchemy-client 投入・親 `client/`・world-server nif のみ |
