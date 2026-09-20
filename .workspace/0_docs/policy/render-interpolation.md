# ポリシー: プレイヤー補間 — クライアント側 render_interpolation

> 作成日: 2026-03-08  
> 最終更新: 2026-07-23  
> ステータス: 採用

---

## 1. 方針

- **主時間**は Elixir の権威 tick（推奨 **20Hz**。設定で 10 / 30 / 非推奨 60）。正本: [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md)
- **表示時間**はクライアント描画（既定 ~60fps）
- **予測・補間**はクライアント側で実装し、権威スナップショットの間を埋める（主時間契約のクライアント側本体）
- **2D 補間**: 廃止（分散型 VRSNS は基本 3D のため不要）
- 旧 nif/physics にあった補間ロジックの系譜は、クライアントの `shared` / `render_interpolation` 相当へ（[legacy_physics.md](../architecture/rust/nif/legacy_physics.md) は参照用）

---

## 2. クレート／モジュール

現状は `rust/client/shared` の補間ユーティリティ（例: `interp.rs`）を描画経路へ配線する。名称は実装に合わせてよい。

- 依存が深くなりすぎるとテストが通りにくくなるため、ロジックは薄いモジュールに保つ

---

## 3. 責務

- サーバー: 権威 tick でフレーム（必要なら prev/curr pose・tick メタデータ）を publish
- クライアント: 受信スナップショットを表示時刻で補間（および必要なら予測）し、描画に反映。公式状態は書き換えない

---

## 4. 関連

- [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md)
- [rust_client.md](../policy-as-code/rust_client.md)
- [scale-and-gaps.md](../policy-as-code/gaps/scale-and-gaps.md)（アルゴリズム具体化のギャップ）
