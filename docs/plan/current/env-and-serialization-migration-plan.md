# 環境変数リネーム・Erlang term 直列化 対応計画書

> 作成日: 2026-03-08  
> 目的: 環境変数のリネーム（GAME_ プレフィックス削除）と、MessagePack から Erlang term 形式への移行を体系的に進める。  
> **実施済み**: §1 環境変数リネーム、§2 MessagePack → Erlang term 直列化（フェーズ A/B/C）→ [env-and-serialization-migration-completed.md](../completed/env-and-serialization-migration-completed.md)

---

## 要約

| 項目 | 状態 | 工数目安 |
|:---|:---|:---|
| 1. 環境変数リネーム | ✅ 完了 | — |
| 2. Erlang term 直列化 | ✅ 完了（フェーズ A/B/C） | — |
| 3. set_cursor_grabbed 抽象化 | 未実施 | 0.5〜1 日 |
| 4. native/client 作成（§5） | 未実施 | 要検討 |

---

## 1. set_cursor_grabbed の抽象化

### 1.1 背景

現状、`desktop_input` 内の `DesktopApp::set_cursor_grabbed` は winit の `window.set_cursor_visible` / `set_cursor_grab` を直接呼ぶ private メソッドであり、トレイトやブリッジ経由で抽象化されていない。ESC によるカーソルグラブ切替の意味づけは contents 層（InputComponent）で行われ、`frame.cursor_grab` としてクライアントへ渡される。プラットフォーム差（例: 別 UI フレームワーク利用）やテスタビリティを考慮し、カーソルグラブの実行を抽象化する。

### 1.2 方針

- **RenderBridge** または新規トレイト（例: `CursorGrabHandler`）に `set_cursor_grabbed(&self, grabbed: bool)` を追加
- `DesktopApp` はそのメソッドを呼び出し、実装は `DefaultCursorGrabHandler`（winit 直接呼び出し）に委譲
- テスト時やヘッドレス時はモック実装に差し替え可能にする

### 1.3 工数目安

0.5〜1 日（既存フローへの組み込み・既存テストの確認含む）

---

## 2. native/client 作成・client_info ・client_* 依存整理 実行計画

### 2.1 背景

- クライアント共通ロジック（Zenoh 接続、エンコード/デコード、クライアント情報取得等）を `native/client` に集約する
- `platform_info` はクライアント属性全般を扱うため、`client_info` とする
- `client_desktop`, `client_web`, `client_android`, `client_ios` は `native/client` に依存し、プラットフォーム固有部分のみを実装する

### 2.2 対象クレート

| クレート | 役割 |
|:---|:---|
| `native/client` | 共有ライブラリ。Zenoh 接続、Erlang term エンコード/デコード、`client_info`（OS/arch 等）の提供 |
| `native/client_desktop` | Windows/Linux/macOS 向け。`client` + `desktop_render` + `desktop_input` に依存 |
| `native/client_web` | Web 向け（将来）。`client` に依存 |
| `native/client_android` | Android 向け（将来）。`client` に依存 |
| `native/client_ios` | iOS 向け（将来）。`client` に依存 |

### 2.3 実行手順

#### フェーズ D1: native/client クレート作成

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| D1-1 | `native/client` ディレクトリ・`Cargo.toml` 作成 | `native/client/Cargo.toml` |
| D1-2 | `client_info` モジュール作成（OS, arch, family 取得。`std::env::consts` 使用、winit 非依存） | `native/client/src/client_info.rs` |
| D1-3 | Zenoh 関連型・エンコード/デコードを `client` へ移動（`network_render_bridge` の共通部分、`bert_decode` 等） | `native/client/src/` |
| D1-4 | ワークスペース `native/Cargo.toml` に `client` を追加 | `native/Cargo.toml` |

#### フェーズ D2: client_info の提供

| ステップ | 内容 | 備考 |
|:---|:---|:---|
| D2-1 | `ClientInfo` 構造体（`os`, `arch`, `family`）を定義 | `platform_info` ではなく `client_info` とする |
| D2-2 | `ClientInfo::current()` で `std::env::consts` から取得 | Windows, Linux, macOS, Android, iOS 対応 |
| D2-3 | Erlang term 形式でシリアライズ可能にする | Zenoh 経由で Elixir へ送信するため |

#### フェーズ D3: client_* の client 依存化

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| D3-1 | `client_desktop` の `Cargo.toml` に `client = { path = "../client" }` を追加 | `native/client_desktop/Cargo.toml` |
| D3-2 | `client_desktop` から `client` へ移したモジュールを削除し、`client::` を参照 | `native/client_desktop/src/*.rs` |
| D3-3 | `client_web`, `client_android`, `client_ios` の `Cargo.toml` に `client` 依存を追加 | 各 `Cargo.toml` |
| D3-4 | 将来的な実装時に `client` の共通 API を利用するようにする | スタブのままでも依存だけ追加 |

### 2.4 依存関係図（移行後）

```
native/client          ← 共有: client_info, Zenoh 接続, エンコード/デコード
    ↑
    ├── client_desktop ← desktop_render, desktop_input
    ├── client_web     ← 将来: wasm-bindgen 等
    ├── client_android ← 将来: ndk 等
    └── client_ios     ← 将来: objc 等
```

### 2.5 実施順序

- **D1, D2** を先行。`client` に `client_info` と共通ロジックを実装
- **D3** で各 `client_*` を `client` に依存させる。`client_desktop` から共通部分を `client` へ移行
- 環境変数リネーム・Erlang term 移行と並行可能。`client` 作成時に `bert` を導入すれば、移行先の型を `client` に集約できる

### 2.6 関連ドキュメント

- [platform-info-crate-and-local-user-execution-plan.md](../completed/platform-info-crate-and-local-user-execution-plan.md) — `platform_info` → `client_info` に読み替え。`client` 配下に配置する想定で更新すること

---

## 3. 実施順序の推奨（残作業）

1. **set_cursor_grabbed の抽象化**（任意・独立）
   - desktop_input のリファクタ。直列化移行とは独立して実施可能

2. **native/client 作成**（フェーズ D1〜D3）
   - クライアント共通ロジックの集約。現状の `native/app`, `native/network` 構成を踏まえて計画を調整すること

---

## 4. 関連ドキュメント

- [zenoh-frame-serialization.md](../../policy-as-code/why_adopted/zenoh-frame-serialization.md) — Erlang term 採用ポリシー
- [erlang-term-schema.md](../../architecture/erlang-term-schema.md) — 実施済みスキーマ
- [messagepack-schema.md](../../architecture/messagepack-schema.md)（非推奨・erlang-term-schema へ誘導）
- [bottleneck-prevention.md](../../policy/bottleneck-prevention.md)（ボトルネック対策方針）
- [desktop/input.md](../../architecture/rust/desktop/input.md)（set_cursor_grabbed の現状・ESC と contents 層の責務）
