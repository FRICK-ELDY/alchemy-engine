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

**目標**

- `weapon_slots` → Elixir 側 Rule state で管理し、Rust には `add_weapon` NIF 経由でのみ反映
- `boss` → Elixir 側 Rule state で管理し、Rust には `spawn_boss` NIF 経由でのみ反映
- `hud_*` フィールド群 → `set_hud_level_state` NIF の引数として毎フレーム注入する形に統一

**影響ファイル**

- `native/game_simulation/src/world/mod.rs` — `GameWorldInner` のフィールド整理
- `native/game_nif/src/render_snapshot.rs` — HUD データ取得方法の変更
- `apps/game_engine/lib/game_engine/game_events.ex` — 毎フレームの状態注入ロジック

---

## 新しいコンテンツを追加する際の手順

2つ目のコンテンツを追加する場合は、以下の手順に従うこと。

1. `WorldBehaviour` を実装した新モジュールを作成し、`setup_world_params/1` で `set_entity_params` NIF に `FirePattern` ベースの武器パラメータを注入する
2. `RuleBehaviour` を実装した新モジュールを作成する（`initial_weapons/0` を含む）
3. `config :game_server, current_world: NewWorld, current_rule: NewRule` を設定する

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
