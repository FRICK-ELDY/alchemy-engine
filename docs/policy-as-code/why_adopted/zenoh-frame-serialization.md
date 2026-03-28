# ポリシー: Zenoh フレーム直列化形式（歴史的経緯と現行）

> 作成日: 2026-03-08  
> 最終更新: 2026-03-28  
> ステータス: 記録（現行は protobuf のみ）

> **現行**: Zenoh のサーバー→クライアント **RenderFrame** は **protobuf**（`proto/render_frame.proto`、Elixir `Alchemy.Render.RenderFrame`、Rust `render_frame_proto::decode_pb_render_frame`）。  
> 契約と手順は [erlang-term-schema.md](../../architecture/erlang-term-schema.md)（レガシー ETF 参照）、[protobuf-migration.md](../../architecture/protobuf-migration.md)、[zenoh-protocol-spec.md](../../architecture/zenoh-protocol-spec.md) を参照。

---

## 1. 歴史（当初の検討）

当初は Erlang term（`:erlang.term_to_binary/1`）や比較対象としての他形式が議論された。**現在のワイヤ形式は protobuf に統一済み**。

---

## 2. protobuf を主経路にした理由（要約）

| 観点 | 内容 |
|:---|:---|
| **スキーマ** | `.proto` を単一情報源にできる |
| **言語横断** | Elixir・Rust で同一ワイヤを共有しやすい |
| **性能** | フレーム毎のエンコード／デコード負荷を制御しやすい |

---

## 3. 関連ドキュメント

- [zenoh-protocol-spec.md](../../architecture/zenoh-protocol-spec.md)
- [draw-command-spec.md](../../architecture/draw-command-spec.md)
- [protobuf-migration.md](../../architecture/protobuf-migration.md)
