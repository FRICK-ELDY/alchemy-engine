# Rust ディレクトリ再編 — `native/` → `rust/`（単一ワークスペース）

> **状態**: 未着手（Definition of Ready 想定）  
> **目的**: リポジトリ直下の見通しを良くし、**サーバ NIF**・**クライアント用クレート群**・**ランチャー**の役割をディレクトリ名で区別する。  
> **方針**: **`rust/Cargo.toml` を唯一のワークスペース根**とし、`members` に `nif` / `launcher` / `client/*` クレートを**列挙**する（`Cargo.lock`・`target/` を一元化）。

---

## 1. 背景

- 現状 `native/` には Rustler NIF（`nif`）とデスクトップクライアント系（`app`, `render`, …）が同居しており、「native＝全部」になりがち。
- 会話で合意した整理:
  - **`rust/nif`**: Elixir（`Core.NifBridge`）からロードする Formula VM 用。**サーバ寄り境界**。
  - **`rust/client/`**: クライアント用クレートを論理グループとして配置（`shared` / `render_frame_proto` は**クライアント・サーバ契約**も含むが、ビルド上は同じワークスペースのメンバー）。
  - **`rust/launcher`**: router / server / client 起動などの**オーケストレーション**（現 `native/tools/launcher`）。

---

## 2. 目標ディレクトリ構成（要約）

```
alchemy-engine/
├── rust/
│   ├── Cargo.toml              # [workspace] — members は下記を列挙
│   ├── Cargo.lock              # 現 native/Cargo.lock を移行（パス更新後に cargo で再生成可）
│   ├── nif/                    # Rustler NIF（Formula VM のみ）
│   ├── launcher/               # システムトレイ起動ツール（旧 tools/launcher）
│   └── client/
│       ├── shared/
│       ├── render_frame_proto/
│       ├── network/
│       ├── audio/
│       ├── render/
│       ├── window/
│       ├── xr/
│       └── app/
├── apps/
│   └── core/lib/core/nif_bridge.ex   # path: "../../rust/nif"（要更新）
└── ...
```

**削除**: 移行完了後、空になった **`native/` ディレクトリは削除**（履歴は Git に残る）。

---

## 3. Cargo ワークスペース（ベストプラクティス）

| 項目 | 内容 |
|:---|:---|
| ワークスペース | **`rust/Cargo.toml` 1 本**のみ |
| `members` | `nif`, `launcher`, `client/shared`, `client/render_frame_proto`, `client/network`, `client/audio`, `client/render`, `client/window`, `client/xr`, `client/app` |
| `resolver` | 現行どおり `"2"` を維持 |
| `profile` | 現 `native/Cargo.toml` の `[profile.dev]` / `[profile.release]` を **`rust/Cargo.toml` に移す** |

**補足**: `rust/client/` は Cargo の「ネストした仮想ワークスペース根」には**しない**。親の `members` に各クレートパスを直接書く（初心者向けに迷いが少ない）。

---

## 4. 依存パス（クレート間 `path =`）

現状は `native/` 直下で兄弟参照（例: `../shared`）。移行後は **`rust/client/` 直下にクレートを並べる**ため、**相対パスは基本的にそのまま**（例: `client/app` から `../shared`）。

確認すること:

- 各 `client/*/Cargo.toml` の `path = "../…​"` が、移動後も正しい兄弟関係になること。
- **`rust/nif`** は現状どおり **他クレートへの path 依存なし**（`Cargo.toml` 確認済みならそのまま）。

---

## 5. 実装手順（推奨順）

### フェーズ A — 機械的移動（1 PR 推奨）

1. **`rust/` を新設**し、ルート `native/Cargo.toml` を **`rust/Cargo.toml` にコピー移行**（中身は次項で更新）。
2. **`members` を新パスに書き換え**（§2 の列挙と一致させる）。
3. ディレクトリ移動（Git で `git mv` 推奨。履歴が追いやすい）:
   - `native/nif` → `rust/nif`
   - `native/tools/launcher` → `rust/launcher`
   - `native/{shared,render_frame_proto,network,audio,render,window,xr,app}` → `rust/client/` 配下へそれぞれ
4. **`Cargo.lock`**: `rust/Cargo.lock` として置く（元 `native/Cargo.lock` を移動）。ルートで `cd rust && cargo build --workspace` を実行し、**ロックが解決するか確認**（差分が出たらコミット）。
5. **`target/`**: `.gitignore` 更新後、`rust/target/` にビルド成果物が出ることを確認。古い `native/target/` は削除（未追跡ならフォルダごと消してよい）。

### フェーズ B — Elixir / ツール連携

6. **`apps/core/lib/core/nif_bridge.ex`**  
   `use Rustler, …, path: "../../native/nif"` → **`path: "../../rust/nif"`**。
7. **`.gitignore`**  
   - `native/target/` → **`rust/target/`** に変更  
   - `native/game_native/target/` がまだ意味を持つか確認し、不要なら削除またはコメント整理  
   - `priv/native/` は Rustler 生成物のため**パターンは維持**（パスは mix が解決）。
8. **GitHub Actions** — `.github/actions/alchemy-ci-setup/action.yml`  
   `workspaces: native` → **`workspaces: rust`**（rust-cache のキャッシュキー用）。
9. **`.github/workflows/ci.yml.ignore`**（または有効化中の CI）  
   `native/Cargo.toml` → **`rust/Cargo.toml`** に置換。
10. **`development.md`**  
    見出し・コマンド例の `native` → **`rust`**（例: `cd rust && cargo build -p nif -p app`）。

### フェーズ C — ドキュメント

11. **`docs/architecture/overview.md`** — ディレクトリツリー、mermaid のパス、本文の `native/` 表記。
12. **`docs/architecture/` 以下**（`rust/nif.md`, `elixir/core.md`, `vision.md`, `draw-command-spec.md`, `erlang-term-schema.md` 等）— **`native/` → `rust/`** への一括置換は **レビュー付き**で（歴史的文脈で `native` を残したい箇所がないか確認）。
13. **`native/nif/README.md` は `rust/nif/README.md` に移る**ため、文中の `native/Cargo.toml` 等を更新。
14. **`workspace/` 配下の古い計画**（`1_backlog/native-restructure-migration-plan.md` 等）は、冒頭に **「2026-04 以前のクレート再編計画。現行パスは `rust/`」** と注記するか、本ドキュメントへリンクする（任意）。

### フェーズ D — 検証

15. **Rust**（リポジトリルートまたは `rust/`）:
    - `cargo fmt --manifest-path rust/Cargo.toml --all -- --check`
    - `cargo clippy --manifest-path rust/Cargo.toml --workspace`
    - `cargo test --manifest-path rust/Cargo.toml -p nif`（および必要なら `-p app` 等）
16. **Elixir**:
    - `mix compile`（NIF が `rust/nif` からビルド・ロードされること）
    - 既存の `mix test`（少なくとも `:core` 関連）

---

## 6. 完了条件（Definition of Done）

- [ ] `native/` がリポジトリからなくなり、**`rust/` に一本化**されている。
- [ ] **`rust/Cargo.toml` の `members`** が §2 と整合し、`cargo build --workspace` が通る。
- [ ] **`Core.NifBridge`** の Rustler `path` が `rust/nif` を指す。
- [ ] **CI 用設定**（rust-cache workspace、manifest-path）が更新されている。
- [ ] **主要アーキテクチャドキュメント**（最低限 `overview.md` と `development.md`）が新パスを反映している。

---

## 7. リスク・注意

| リスク | 緩和 |
|:---|:---|
| ローカルに残った `native/target` の巨大キャッシュ | 開発者向けに「古い `native/target` は削除可」と development に一行。 |
| 外部スクリプト・個人メモが `cd native` のまま | リポジトリ内 grep で `native/` を再確認。 |
| ドキュメント大量の置換で誤変換 | 一括置換より、**grep リストを取ってから**段階的に。評価アーカイブ（`docs/evaluation/*`）は優先度を下げてよい。 |

---

## 8. 関連ドキュメント

- 過去のクレート名再編（歴史）: [workspace/1_backlog/native-restructure-migration-plan.md](../1_backlog/native-restructure-migration-plan.md) — **現行の「フォルダ名 native → rust」タスクとは別フェーズの記録**。
- アーキ概要: [docs/architecture/overview.md](../../docs/architecture/overview.md)

---

## 9. 作業見積もり（目安）

| 項目 | 目安 |
|:---|:---|
| 移動 + Cargo 修正 + Elixir + CI + ignore | 0.5〜1 日 |
| docs 全体のパス追随 | 0.5〜1 日（範囲を切ると短縮） |

（初回 `cargo build --workspace` で依存の再解決に時間がかかる場合あり。）
