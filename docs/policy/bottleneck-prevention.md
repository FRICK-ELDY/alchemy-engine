# ポリシー: ボトルネックの事前対策

> 作成日: 2026-03-08  
> ステータス: 採用

---

## 1. 方針

分散型 VRSNS ではエンティティ数（他プレイヤー・アバター等）の増加が想定される。  
**初期段階でボトルネックをつぶしておく**。

---

## 2. 該当分野と対応

| 分野 | 想定ボトルネック | 対応 |
|:---|:---|:---|
| **Zenoh フレーム直列化** | 60Hz のエンコード/デコード負荷 | protobuf（`proto/render_frame.proto`）でワイヤ形式を固定し、Elixir / Rust で同一スキーマを共有 |
| **補間** | サーバー側での補間は負荷・遅延の要因 | クライアント側に移す（render_interpolation） |

---

## 3. 関連

- [zenoh-frame-serialization](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
- [render-interpolation](./render-interpolation.md)
