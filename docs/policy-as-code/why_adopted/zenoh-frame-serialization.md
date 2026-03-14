# ポリシー: Zenoh フレーム直列化形式 — Erlang term 採用

> 作成日: 2026-03-08  
> ステータス: 採用

---

## 1. 方針

Zenoh によるサーバー→クライアントの RenderFrame 配信において、**Erlang term 形式**（`:erlang.term_to_binary/1`）を用いる。

MessagePack は使用しない。

---

## 2. 理由

### 2.1 ボトルネック対策

- 分散型 VRSNS ではエンティティ数（他プレイヤー・アバター等）が増える見込み
- 60Hz フルフレームのエンコード／デコード負荷を初期段階から抑えたい
- MessagePack（Msgpax）は純 Elixir 実装のため、ネイティブ実装より遅くなりうる

### 2.2 Erlang term の利点

| 観点 | 内容 |
|:---|:---|
| **Elixir 側** | `term_to_binary` は C 実装の BIF。最も高速 |
| **圧縮** | `:compressed` オプションで zlib 圧縮可能。ペイロード削減 |
| **NIF 親和性** | Rustler の `BinaryTerm` デコードや `bert` クレートで Rust から扱える |
| **型の保持** | Elixir のタプル・マップ・アトムをそのまま表現。変換ロスなし |

### 2.3 トレードオフ

- **他言語サーバー**: Elixir 専用サーバーを前提とするため、将来的に非 Elixir サーバーを立てる場合は別フォーマットが必要
- **スキーマ検証**: MessagePack と異なりスキーマレス。型の契約はドキュメントとテストで担保する

---

## 3. 実装方針

### 3.1 サーバー（Elixir）

```elixir
# フレームを Elixir の term としてバイナリ化
frame_term = %{
  commands: [...],
  camera: {:camera_3d, ...},
  ui: %{nodes: [...]},
  mesh_definitions: [],
  # 拡張: player_interp, cursor_grab 等
}
binary = :erlang.term_to_binary(frame_term, [:compressed])
Network.ZenohBridge.publish_frame(room_id, binary)
```

### 3.2 クライアント（Rust）

- `bert` クレートまたは `rustler` の `BinaryTerm` でデコード
- 既存の `msgpack_decode` を `bert_decode`（または同等）に置き換え

### 3.3 データ構造

トップレベル構造は [messagepack-schema.md](../../architecture/messagepack-schema.md) の設計を踏襲する。キーをアトムに変更し、タプル・マップをそのまま用いる。

| 項目 | MessagePack 時 | Erlang term 時 |
|:---|:---|:---|
| マップキー | 文字列 `"commands"` | アトム `:commands` |
| DrawCommand | `%{"t" => "sprite_raw", ...}` | `{:sprite_raw, x, y, w, h, ...}` またはマップ |
| Camera | `%{"t" => "camera_3d", ...}` | `{:camera_3d, eye, target, up, fov, near, far}` |

---

## 4. 移行手順

1. `Content.MessagePackEncoder` を `Content.FrameEncoder` 等にリネームし、`term_to_binary` を用いる実装に変更
2. クライアント側 `msgpack_decode` を `bert` デコードに置き換え
3. [messagepack-schema.md](../../architecture/messagepack-schema.md) を `erlang-term-schema.md` 等に拡張し、term 形式のスキーマを文書化
4. 既存の MessagePack 参照を更新

---

## 5. 関連ドキュメント

- [improvement-plan.md](../../plan/reference/improvement-plan.md)（I-P render_interpolation によるフレーム拡張）
- [zenoh-protocol-spec.md](../../architecture/zenoh-protocol-spec.md)
- [messagepack-schema.md](../../architecture/messagepack-schema.md)（現行スキーマ・構造の参照）
