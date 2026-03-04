# コンテンツ制作エンジンへのリネーム計画

> 作成日: 2026-03-04  
> 目的: プロジェクトを「ゲームエンジン」から「コンテンツ制作エンジン」へ舵を切り、「game」文言をエンジン層から排除する。

---

## 1. 背景・方針

### 1.1 背景

- プロジェクトはゲームエンジンを超え、汎用コンテンツ制作エンジンへ発展している
- エンジン層は「コンテンツ」を知るが「ゲーム」を知らない設計にしたい

### 1.2 「game」禁止ルール

| 対象 | 「game」使用 |
|:---|:---|
| `apps/contents`（旧 game_content）内 | **許可** — コンテンツ固有ロジック（例: game_over シーン、VampireSurvivor 等） |
| 上記以外の全箇所 | **禁止** — モジュール名・アプリ名・設定キー・パス・コメント |

---

## 2. リネーム一覧

### 2.1 Elixir アプリ

| 現名称 | 新名称 | モジュール名前空間 |
|:---|:---|:---|
| `apps/game_content` | `apps/contents` | `GameContent.*` → `Content.*` |
| `apps/game_engine` | `apps/core` | `GameEngine.*` → `Core.*` |
| `apps/game_network` | `apps/network` | `GameNetwork.*` → `Network.*` |
| `apps/game_server` | `apps/server` | `GameServer.*` → `Server.*` |

### 2.2 Native（Rust）クレート

| 現名称 | 新名称 |
|:---|:---|
| `native/game_audio` | `native/audio` |
| `native/game_input` | `native/input` |
| `native/game_physics` | `native/physics` |
| `native/game_render` | `native/render` |

### 2.3 NIF ブリッジ・XR 入力

| 現名称 | 新名称 |
|:---|:---|
| `native/game_nif` | `native/nif` |
| `native/game_input_openxr` | `native/input_openxr` |

---

## 3. 段階的実施フェーズ

段階的に進め、各フェーズ完了後に `mix compile` / `cargo build` で動作確認する。

### フェーズ 0: 準備（事前確認）

- [ ] 全テスト・CI が現状で通ることを確認
- [ ] 計画書のレビュー・ゲーム文言禁止対象の最終確定

---

### フェーズ 1: Native クレートのリネーム ✅ 完了

Rust 側のクレート名・ディレクトリを先に変更。Elixir からは `game_nif` 経由で参照されるため、`game_nif` はこのフェーズでは変更しない。

| # | タスク | 対象 | 状態 |
|:---:|:---|:---|:---:|
| 1.1 | `game_audio` → `audio` | ディレクトリ移動、Cargo.toml、`native/Cargo.toml` members、`game_nif` の依存 | ✅ |
| 1.2 | `game_input` → `input` | 同上。`game_input_openxr` が依存する場合は後述フェーズで対応 | ✅ |
| 1.3 | `game_physics` → `physics` | 同上 | ✅ |
| 1.4 | `game_render` → `render` | 同上 | ✅ |
| 1.5 | `game_input_openxr` → `input_openxr` | ディレクトリ、Cargo.toml、`game_nif` の optional 依存 | ✅ |

**注意:** 各クレート内の `use game_xxx::` 等の参照をすべて `use xxx::` に置換する。

---

### フェーズ 2: `game_nif` のリネーム ✅ 完了

| # | タスク | 対象 | 状態 |
|:---:|:---|:---|:---:|
| 2.1 | `game_nif` → `nif` | ディレクトリ、Cargo.toml、`native/Cargo.toml` members、Rustler（crate/path）、config | ✅ |
| 2.2 | `nif` の内部参照 | `game_physics` → `physics`、`game_audio` → `audio` 等（Phase 1 で変更済み） | ✅ |
| 2.3 | `game_input_openxr` → `input_openxr` | `nif` の features 内の参照（Phase 1.5 で変更済み） | ✅ |

---

### フェーズ 3: Elixir アプリのリネーム（core から）✅ 完了

`core`（旧 game_engine）が NIF をロードするため、core を先にリネームする。

| # | タスク | 対象 | 状態 |
|:---:|:---|:---|:---:|
| 3.1 | `game_engine` → `core` | ディレクトリ `apps/game_engine` → `apps/core`、`lib/game_engine` → `lib/core` | ✅ |
| 3.2 | モジュール `GameEngine.*` → `Core.*` | 全ファイル | ✅ |
| 3.3 | mix.exs | `app: :core`、Rustler の `otp_app: :core` | ✅ |
| 3.4 | config | `config :game_engine, ...` → `config :core, ...` | ✅ |
| 3.5 | 他アプリの依存 | `{:game_engine, in_umbrella: true}` → `{:core, in_umbrella: true}` | ✅ |
| 3.6 | NIF | `rustler::init!("Elixir.Core.NifBridge", ...)` | ✅ |

---

### フェーズ 4: Elixir アプリのリネーム（network / server）✅ 完了

| # | タスク | 対象 | 状態 |
|:---:|:---|:---|:---:|
| 4.1 | `game_network` → `network` | ディレクトリ、モジュール、mix.exs、config | ✅ |
| 4.2 | `game_server` → `server` | 同上。`config :game_server` → `config :server` | ✅ |
| 4.3 | 環境変数 | `GAME_NETWORK_PORT` → `NETWORK_PORT`、`GAME_NETWORK_UDP_PORT` → `NETWORK_UDP_PORT` | ✅ |

---

### フェーズ 5: Elixir アプリのリネーム（contents）

| # | タスク | 対象 |
|:---:|:---|:---|
| 5.1 | `game_content` → `contents` | ディレクトリ `apps/game_content` → `apps/contents` |
| 5.2 | モジュール `GameContent.*` → `Content.*` | 全ファイル。`lib/game_content` → `lib/contents` |
| 5.3 | mix.exs | `app: :contents`、依存 `{:game_engine, ...}` → `{:core, ...}` |
| 5.4 | config | `GameContent.SimpleBox3D` → `Content.SimpleBox3D` 等 |
| 5.5 | 他アプリの依存 | `{:game_content, in_umbrella: true}` → `{:contents, in_umbrella: true}` |

---

### フェーズ 6: 設定・スクリプト・ドキュメント

| # | タスク | 対象 |
|:---:|:---|:---|
| 6.1 | config/runtime.exs | キー名・モジュール参照の更新 |
| 6.2 | bin/*.bat, bin/*.sh | パス・コメントの更新 |
| 6.3 | CI（.github/workflows） | クレート名・アプリ名の更新 |
| 6.4 | docs/*.md | ドキュメント内の旧名称の置換 |
| 6.5 | .cursor/rules/*.mdc | ルール内の `game_engine`、`game_nif` 等の文言更新 |
| 6.6 | GAME_ASSETS_ID 等 | 環境変数名を `CONTENT_ASSETS_ID` 等に変更するか検討 |

---

### フェーズ 7: 文言禁止の徹底・ルール化

| # | タスク | 対象 |
|:---:|:---|:---|
| 7.1 | grep による残存確認 | `contents` 外で `game_` が残っていないか検索 |
| 7.2 | 実装ルールへの追記 | 「game 文言は `apps/contents` 内のみ許可」を明文化 |
| 7.3 | Credo 等のチェック | カスタムルールで禁止パターンを検出するか検討 |

---

## 4. 影響範囲サマリ

### 4.1 依存関係（リネーム後）

```
core (旧 game_engine)
  └── NIF: nif (旧 game_nif)
        ├── physics (旧 game_physics)
        ├── audio (旧 game_audio)
        ├── input (旧 game_input)
        ├── render (旧 game_render)
        └── input_openxr (旧 game_input_openxr, optional)

contents (旧 game_content)
  └── core

network (旧 game_network)
  └── core

server (旧 game_server)
  └── core, contents, network
```

### 4.2 主な更新対象ファイル

- **Mix:** `apps/*/mix.exs`（全4アプリ）
- **Config:** `config/config.exs`, `config/runtime.exs`
- **NIF:** `apps/core/priv/native/` の DLL パス、Rustler の `path` / `crate`
- **Rust:** `native/Cargo.toml`, 各クレートの `Cargo.toml` および内部 `use`
- **ドキュメント:** `docs/`, `README.md`, `.cursor/rules/`

---

## 5. リスク・注意点

- **ビルド破損:** フェーズごとに `mix compile` / `cargo build` で確認し、問題があれば即ロールバック
- **git 履歴:** ディレクトリの `git mv` を使い、可能な限り履歴を維持する
- **大規模変更:** 1 PR にまとめず、フェーズごとに PR を分けることを推奨
- **CI:** 各フェーズ完了後に CI が通ることを確認

---

## 6. 次のアクション

1. 本計画書のレビュー・承認
2. フェーズ 0 の実施（準備・事前確認）
3. フェーズ 1 から順に実施
