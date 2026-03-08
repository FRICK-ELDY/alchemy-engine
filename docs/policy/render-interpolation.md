# ポリシー: プレイヤー補間 — クライアント側 render_interpolation

> 作成日: 2026-03-08  
> ステータス: 採用

---

## 1. 方針

- **2D 補間**: 廃止（分散型 VRSNS は基本 3D のため不要）
- **3D 補間**: クライアント側で実装
- **補間ロジック**: 現状 nif/physics にあるものを `render_interpolation` クレートに移す

---

## 2. クレート名

`render_interpolation`（`desktop_` プレフィックスは付けない）

- 依存が深くなりすぎるとテストが通りにくくなるため、シンプルな名前にする

---

## 3. 責務

- サーバー: フレームに `player_interp`（prev/curr pose, tick）を含めて publish
- クライアント: `render_interpolation` で補間し、描画に反映

---

## 4. 関連

- [improvement-plan.md](../plan/improvement-plan.md)（I-P render_interpolation）
