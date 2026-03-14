# ポリシー: NIF と desktop の分離 — Zenoh 専用

> 作成日: 2026-03-08  
> ステータス: 採用

---

## 1. 方針

- **NIF（サーバー側）** は `desktop_render` および `desktop_input` に依存しない
- **クライアント側**（描画・入力）は `client_desktop` として別プロセスで動作
- **サーバー・クライアント間の通信は Zenoh のみ**。ローカルモード（同一プロセス内レンダー）は廃止

---

## 2. 理由

- サーバーとクライアントの責務を明確に分離
- 分散型 VRSNS ではクライアント分離が前提
- 二重経路（NIF ローカル / Zenoh リモート）の維持コストを排除

---

## 3. 影響

- 開発時は常に `zenohd + mix run + client_desktop` の 3 プロセス構成
- `mix run` 単体ではウィンドウは開かない（ヘッドレス）

---

## 4. 関連

- [improvement-plan.md](../plan/reference/improvement-plan.md)（I-P render_interpolation, I-Q VR xr フィーチャー）
- [zenoh-frame-serialization](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
