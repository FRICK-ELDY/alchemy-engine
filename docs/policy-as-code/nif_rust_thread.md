# Policy: NIF × Rust スレッド — 責務分担・Dirty NIF・委譲

[← index](./index.md)

> **2026-04 更新**: ゲーム用 Rust 専用スレッド（旧 `GameWorld` / `physics_step` / 60Hz サーバーループ）は **撤去済み**。サーバー側 NIF は **`run_formula_bytecode`（Formula VM）** を主とする。ゲーム状態の刻みは **Elixir（contents）のタイマー**（[architecture/overview.md](../architecture/overview.md)）。

---

## 1. 重い処理は Rust の独自スレッドで行う（クライアント／ネイティブ側）

**やってはいけないこと**: 重い演算・大量データ処理を **通常 NIF** 内（スケジューラスレッド上）で同期的に実行すること。

**理由**:

- NIF は BEAM のスケジューラスレッドを占有する
- 重い処理を NIF に載せると、VM 全体の応答性が低下する
- サーバー側の「数式」は Formula VM（`run_formula_bytecode`）に載せ、それ以外の重い処理は **クライアント／別プロセスの Rust** に委譲する

**やるべきこと**: サーバー NIF は Formula 呼び出し・起動・軽量な境界操作に限定する。描画・入力・デコードの高頻度ループは **クライアント／`rust/client/app` 等**の Rust で行う（[rust_client.md](./rust_client.md)）。

---

## 2. 長時間 NIF が必要な場合は Dirty NIF または委譲を検討する

**やってはいけないこと**: 1ms 超の処理を通常 NIF で同期的に実行すること。

**やるべきこと**:

- **Dirty NIF**: `#[rustler::nif(schedule = "DirtyCpu")]` を用い、専用スレッドで実行させる。ただし dirty スレッド数には上限がある
- **委譲**: 処理を Rust の非同期タスクやチャネル経由で別スレッドに渡し、NIF は即座に返す。結果が必要な場合は Elixir へメッセージで非同期に返す

---

## 3. NIF とゲーム刻みの境界を明確にする

**やってはいけないこと**: 「1 フレームにつき何十回も NIF を叩いてサーバー側の物理世界を進める」ような設計に戻すこと（旧ゲーム NIF の再導入）。

**やるべきこと**: ゲーム刻みは **Elixir** がスケジュールし、必要な数式は **`run_formula_bytecode`** に集約する。ワイヤ上の描画・入力は protobuf / Zenoh でクライアントと同期する。予測・補間はクライアント側で行う（[rust_client.md](./rust_client.md)）。
