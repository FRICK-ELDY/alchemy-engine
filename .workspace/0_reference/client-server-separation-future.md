# クライアント・サーバー分離 — 将来対応項目

> 参照: [client-server-separation-procedure.md](../7_done/client-server-separation-procedure.md)（フェーズ 0〜3 は実施済み）
>
> 本ドキュメントは、クライアント・サーバー分離手順書で未実施のフェーズ 4・5 をまとめたものです。

---

## フェーズ 4: ビルド・配布（1 週間）

### 4.1 クライアント exe ビルド

- [ ] `cargo build --release -p app` で Windows exe を生成（※ `client_desktop` は `app` に統合済み）
- [ ] CI にクライアントビルドを追加

### 4.2 アセット・設定

- [ ] クライアント exe と同梱するアセット（atlas.png, shaders）の配置方針
- [ ] Zenoh / サーバー接続先のデフォルト（例: `tcp/localhost:7447` 等、Zenoh の接続形式に準拠）

---

## フェーズ 5: ローカル描画のオプション化（任意・1〜2 週間）

- [ ] サーバーをヘッドレスで起動するモード（`start_render_thread` を呼ばない）

---

## 関連ドキュメント

- [client-server-separation-procedure.md](../7_done/client-server-separation-procedure.md) — 実施済み手順（フェーズ 0〜3）
- [zenoh-protocol-spec.md](../../docs/architecture/zenoh-protocol-spec.md) — Zenoh プロトコル仕様
- [asset-cdn-design.md](../1_backlog/asset-cdn-design.md) — アセット配布設計（将来検討）
