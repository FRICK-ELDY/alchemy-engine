# P5 転送効率化 — 設計ドキュメント

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/contents-defines-rust-executes.md) P5、[contents-to-physics-bottlenecks.md](contents-to-physics-bottlenecks.md) セクション 6

---

## 1. 概要

P5 は Elixir ↔ Rust 間のデータ転送効率化を目的とする。**定義の所在**とは独立だが、定義を渡す際のオーバーヘッドを削減する。


| タスク  | 内容                          | 方針                                       |
| ---- | --------------------------- | ---------------------------------------- |
| P5-1 | バッチ注入 API                   | `set_frame_injection` で複数 write を 1 回に集約 |
| P5-2 | バイナリ形式                      | MessagePack / 自前形式の検討（設計・評価）             |
| P5-3 | push_render_frame decode 低減 | バイナリパス or デコード最適化                        |
| P5-4 | get_render_entities O(n) 削減 | ダブルバッファ・差分更新                             |


---

## 2. P5-1: set_frame_injection バッチ API

### 2.1 現状の課題

毎フレーム 7〜9 回の write lock 取得:

- set_player_input
- set_player_snapshot
- set_elapsed_seconds
- set_weapon_slots
- set_special_entity_snapshot
- set_enemy_damage_this_frame
- (on_frame_event 内: add_score_popup, spawn_item 等は別経路)

### 2.2 設計

**新規 NIF**: `set_frame_injection(world, injection_map)`

`injection_map` は Elixir の map。以下のキーを任意の組み合わせで持つ:


| キー                         | 型                                                         | 適用先                                                  |
| -------------------------- | --------------------------------------------------------- | ---------------------------------------------------- |
| `:player_input`            | `{dx, dy}`                                                | player.input_dx/dy                                   |
| `:player_snapshot`         | `{hp, invincible_timer}`                                  | player_hp_injected, player_invincible_timer_injected |
| `:elapsed_seconds`         | float                                                     | elapsed_seconds                                      |
| `:weapon_slots`            | `[{kind_id, level, cooldown, cooldown_sec, damage}, ...]` | weapon_slots_input                                   |
| `:enemy_damage_this_frame` | `[{kind_id, damage}, ...]`                                | enemy_damage_this_frame                              |
| `:special_entity_snapshot` | `:none` or `{:alive, x, y, radius, damage, invincible}`   | special_entity_snapshot                              |


存在するキーのみ適用。1 回の write lock でまとめて反映。

### 2.3 Elixir 側の収集フロー

1. `throttled?` でない場合、処理開始時に `Process.put(:frame_injection, %{})`
2. `maybe_set_input_and_broadcast`: `player_input` を注入 map にマージ（NIF 呼び出しは行わない）
3. `dispatch_nif_sync_to_components`: 各コンポーネントが `on_nif_sync` で注入 map にマージ
4. ディスパッチ後、`injection = Process.get(:frame_injection, %{})` を取得
5. `injection != %{}` なら `set_frame_injection(world_ref, injection)` を 1 回だけ呼ぶ

### 2.4 後方互換

既存の個別 NIF（set_player_snapshot 等）は残す。段階的移行時、コンテンツがバッチ未対応なら従来どおり個別呼び出し。VampireSurvivor 等はバッチ経由に移行。

---

## 3. P5-2: バイナリ形式の検討

### 3.1 候補


| 形式             | メリット          | デメリット                  |
| -------------- | ------------- | ---------------------- |
| MessagePack    | 既存ライブラリ、型情報   | 依存追加、Elixir 側シリアライズコスト |
| 自前バイナリ         | 最小オーバーヘッド、型固定 | 保守コスト、スキーマ変更の手間        |
| Bincode (Rust) | Rust ネイティブ    | Elixir 側でエンコードが煩雑      |


### 3.2 推奨（フェーズ 1）

**結論**: 現状はタプル形式を維持。P5-3 でデコード最適化を先に行い、ボトルネック計測後にバイナリ化の要否を判断する。

- MessagePack: Elixir に msgpax 等の依存が必要。エンコード/デコードの両側で型マッピングの保守コストあり。
- 自前バイナリ: オーバーヘッド最小だが、DrawCommand のスキーマ変更時に Elixir/Rust 両方を更新する必要あり。P2 で SSoT 文書化が完了してから検討。
- Bincode: Rust ネイティブだが Elixir 側でエンコードが煩雑。Rustler のタプル decode は既に最適化されており、小規模データでは差が小さい。

### 3.3 将来のバイナリ化時

- DrawCommand: タグ 1 byte + 可変長フィールド
- MeshDef: 頂点リストの length-prefixed バイナリ
- エンコードは Elixir で、デコードは Rust で行う

---

## 4. P5-3: push_render_frame decode 低減

### 4.1 現状

- decode_commands: DrawCommand ごとにタプル decode
- decode_ui_canvas: 再帰的ツリー decode
- decode_mesh_definitions: メッシュ定義の map decode

### 4.2 短期的対策

- 同一フレーム内でのデコード結果のメモ化・再利用は困難（毎フレーム新規）
- デコードループのアロケーション削減（Vec::with_capacity 等）
- UiCanvas の差分更新: 変更時のみ送る設計は別タスク

### 4.3 中期的対策

P5-2 のバイナリ形式を採用した場合、バイナリ専用デコードパスを追加。

---

## 5. P5-4: get_render_entities O(n) コピー削減

### 5.1 現状

毎フレーム、敵・弾・パーティクル・アイテムの SoA から `Vec<(f64, f64, ...)>` を新規アロケーションで構築。

### 5.2 方針: ダブルバッファ

1. 描画用バッファ A / B を 2 つ保持
2. `get_render_entities` は「前フレームで書き込み済み」のバッファを返す
3. 物理ステップ後、もう一方のバッファに最新データを書き込み
4. 次の `get_render_entities` ではバッファをスワップ

### 5.3 実装の留意点

- Render スレッドと Elixir の読み取りタイミングのずれ
- スワップのタイミング: `physics_step` 直後 or `drain_frame_events` 時
- 既存の `get_render_entities` の戻り値型（タプル）を維持する必要あり

---

## 6. 実装優先度

1. **P5-1** — 即効性が高く、設計が明確
2. **P5-4** — データ量に比例する効果が大きい
3. **P5-3** — 計測に基づく最適化
4. **P5-2** — 検討・評価フェーズ

