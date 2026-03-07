# set_frame_injection MessagePack 化 — 設計ドキュメント

> 作成日: 2026-03-07  
> 出典: [p5-transfer-optimization-design.md](p5-transfer-optimization-design.md)、[contents-to-physics-bottlenecks.md](contents-to-physics-bottlenecks.md)  
> 参照: [messagepack-schema.md](messagepack-schema.md)（push_render_frame のスキーマパターン）

---

## 1. 概要

`set_frame_injection` NIF は毎フレーム `on_nif_sync` で呼ばれ、Elixir 側でマージした `injection_map` を Rust の GameWorld に適用する。本設計は、この injection_map を MessagePack バイナリで渡す経路を追加し、タプル decode のオーバーヘッドを削減することを目的とする。

| 項目 | 内容 |
|:---|:---|
| 対象 NIF | `set_frame_injection(world, injection_map)` |
| エンコード | Elixir（contents / core）で msgpax によりバイナリ化 |
| デコード | Rust（nif）で rmp-serde によりバイナリから構造体へ変換 |
| 後方互換 | タプル形式パスは残す。段階移行または MessagePack 統一 |

---

## 2. 現行 injection_map の構造

P5-1 で実装済み。`native/nif/src/nif/world_nif.rs` の `set_frame_injection` が受け取る。

| キー | 型 | 説明 |
|:---|:---|:---|
| player_input | `{dx, dy}` | プレイヤー移動入力（float, float） |
| player_snapshot | `{hp, invincible_timer}` | HP と無敵タイマー（float, float） |
| elapsed_seconds | float | 経過秒数 |
| weapon_slots | `[{kind_id, level, cooldown, cooldown_sec, precomputed_damage}, ...]` | 武器スロット。kind_id: u8, level: u32, cooldown: float, cooldown_sec: float, precomputed_damage: i32 |
| enemy_damage_this_frame | `[{kind_id, damage}, ...]` | 敵接触ダメージ。kind_id: u8, damage: float |
| special_entity_snapshot | `:none` \| `{:alive, x, y, radius, damage, invincible}` | ボス等の特殊エンティティ。x,y,radius,damage: float, invincible: bool |

注入元: `game_events.ex`（player_input）、`level_component.ex`（player_snapshot, elapsed_seconds, weapon_slots, enemy_damage_this_frame）、`boss_component.ex`（special_entity_snapshot）、`asteroid_arena/split_component.ex`（enemy_damage_this_frame）等。

---

## 3. MessagePack スキーマ（案）

トップレベルは map。存在するキーのみ pack する（現行と同様、オプショナルキー）。

```elixir
%{
  "player_input" => [dx, dy],
  "player_snapshot" => [hp, invincible_timer],
  "elapsed_seconds" => float,
  "weapon_slots" => [[kind_id, level, cooldown, cooldown_sec, precomputed_damage], ...],
  "enemy_damage_this_frame" => [[kind_id, damage], ...],
  "special_entity_snapshot" => nil | %{"t" => "alive", "x" => x, "y" => y, "radius" => r, "damage" => d, "invincible" => inv}
}
```

- キーは文字列（MessagePack の慣習）
- `special_entity_snapshot`: `nil` で :none、map で {:alive, ...} を表現
- 数値は f64 として pack（Rust 側で必要に応じて f32 等に変換）

---

## 4. 実装方針

1. **エンコーダ**: `Content.MessagePackEncoder` に `encode_injection_map/1` を追加。map のキーを検査し、存在するもののみ MessagePack 用の構造に変換して pack。
2. **デコーダ**: `nif/decode/` に `msgpack_injection.rs` を追加。`decode_injection_from_msgpack` でバイナリを GameWorld に適用する形の構造体に変換。
3. **NIF**: `set_frame_injection_binary(world, binary)` を追加。既存の `set_frame_injection` はタプル用として残す。
4. **呼び出し側**: `game_events.ex` で `map_size(injection) > 0` のときに、MessagePack バイナリを生成して `set_frame_injection_binary` を呼ぶように変更。

---

## 5. 留意点

- `injection_map` はコンテンツによってキーが異なる。キー不在時はスキップする現行の挙動を維持する。
- `weapon_slots` の要素数・`enemy_damage_this_frame` の要素数はフレームごとに変動する。空リストは `[]` として pack。
- スキーマ変更時は本ドキュメントと `messagepack-schema.md`（injection セクション）を更新し、Elixir/Rust 両方を整合させる。

---

## 6. 関連ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [p5-transfer-optimization-design.md](p5-transfer-optimization-design.md) | P5 転送効率化の全体方針 |
| [messagepack-schema.md](messagepack-schema.md) | push_render_frame の MessagePack スキーマ（参考パターン） |
| [set-frame-injection-messagepack-execution-plan.md](../task/set-frame-injection-messagepack-execution-plan.md) | 実施計画 |
