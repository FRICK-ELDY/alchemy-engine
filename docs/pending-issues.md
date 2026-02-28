# AlchemyEngine — 残課題・懸念点

> `vision.md` が定義する Engine / World / Rule の 3 層分離を完成させることが最終目標。
> このドキュメントは未解決の課題と将来への懸念点を管理する。
> 課題が解消されたら該当セクションを削除すること。

---

## 課題一覧

### 課題8: Rust の `GameWorldInner` からルール固有フィールドを除去する

**優先度**: 低（2つ目のコンテンツを作り始めるタイミングで実施）

**背景**

`vision.md` の「目指す姿」に記載の通り、現在の `GameWorldInner` には
`weapon_slots`、`boss`、`hud_level`、`hud_exp`、`hud_exp_to_next`、`hud_level_up_pending`、`hud_weapon_choices`
といった VampireSurvivor 固有のフィールドが残っている。
これらはエンジンが知るべき概念ではなく、Rule 側で管理されるべきものだ。

**現状**

- `weapon_slots` → `add_weapon` NIF で Elixir から操作可能だが、Rust 内部に保持
- `boss` → `spawn_boss` / `set_boss_velocity` 等の NIF で Elixir から制御可能だが、Rust 内部に保持
- `hud_*` フィールド群 → `set_hud_level_state` NIF で毎フレーム注入済み（描画専用）

**目標**

- `weapon_slots` → Elixir 側 Rule state で管理し、Rust には `add_weapon` NIF 経由でのみ反映
- `boss` → Elixir 側 Rule state で管理し、Rust には `spawn_boss` NIF 経由でのみ反映
- `hud_*` フィールド群 → 現状の `set_hud_level_state` NIF 注入方式を維持（対応済み）

**影響ファイル**

- `native/game_simulation/src/world/game_world.rs` — `GameWorldInner` のフィールド整理
- `native/game_nif/src/render_snapshot.rs` — HUD データ取得方法の変更
- `apps/game_engine/lib/game_engine/game_events.ex` — 毎フレームの状態注入ロジック

---

## 新しいコンテンツを追加する際の手順

2つ目のコンテンツを追加する場合は、以下の手順に従うこと。

1. `WorldBehaviour` を実装した新モジュールを作成し、`setup_world_params/1` で `set_entity_params` NIF に新コンテンツのエンティティパラメータを注入する
2. `RuleBehaviour` を実装した新モジュールを作成する（`initial_weapons/0`、`update_boss_ai/2`、`on_entity_removed/4` 等を含む）
3. `config :game_server, current_world: NewWorld, current_rule: NewRule` を設定する
4. 課題8（`GameWorldInner` のフィールド整理）を実施して、エンジンコアから VampireSurvivor 固有の概念を除去する

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
