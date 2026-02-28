# AlchemyEngine — 技術的負債と残課題

> このドキュメントは `roadmap.md` のクローズに伴い、未解決の課題を引き継いだものです。
> `vision.md` が定義する Engine / World / Rule の 3 層分離を完成させることが最終目標です。

---

## 完了済みの作業（参考）

| Phase | 内容 | 完了時期 |
|:---|:---|:---|
| Phase 1（一部） | `context` から `weapon_levels`・`level_up_pending`・`weapon_choices` を除去 | Phase 3-B |
| Phase 2 | `WorldBehaviour`・`RuleBehaviour` の分割、`VampireSurvivorRule` の独立、`GameBehaviour` 廃止マーク | Phase 2 |
| Phase 3-A | `EntityParamTables` の NIF 経由外部注入構造を実装 | Phase 3-A |
| Phase 3-B | ボスAI・レベリング・アイテムドロップを Elixir 移管、`FrameEvent` から `exp`・`LevelUp` を除去 | Phase 3-B |
| Phase 3-C | `skip_level_up`・`get_weapon_levels`・`get_boss_info` NIF を除去、`score_popups` のルール固有計算を Elixir 側に移管 | Phase 3-C |
| 課題1 | `GameEvents.context` のルール固有キー（`level`・`exp`・`boss_*`）をエンジン state から除去し、Playing シーン state で管理 | 技術的負債解消 |
| 課題2 | `entity_params.rs` の `WEAPON_ID_*`・`BOSS_ID_*`・`ENEMY_ID_*` 定数・`exp_reward` フィールド・`name` フィールド・ハードコードデフォルト値を除去、空テーブルに変更 | 技術的負債解消 |
| 課題3 | `weapons.rs` の武器発射ロジックを `FirePattern` ベースの汎用実装に置き換え。`WeaponParams` に `fire_pattern`・`range`・`chain_count` フィールドを追加 | 技術的負債解消 |
| 課題4 | `GameBehaviour` の完全廃止。`vampire_survivor.ex`（後方互換ラッパー）と `game_behaviour.ex` を削除 | 技術的負債解消 |
| 課題5 | `FrameEvent` の `BossDefeated`・`BossSpawn`・`BossDamaged` を `SpecialEntityDefeated`・`SpecialEntitySpawned`・`SpecialEntityDamaged` に汎用化 | 技術的負債解消 |

---

## 残課題

現時点で未解決の技術的負債はありません。

2つ目のコンテンツを追加する場合は、以下の手順に従ってください：

1. `WorldBehaviour` を実装した新モジュールを作成し、`setup_world_params/1` で `set_entity_params` NIF に `FirePattern` ベースの武器パラメータを注入する
2. `RuleBehaviour` を実装した新モジュールを作成する
3. `config :game_server, current_world: NewWorld, current_rule: NewRule` を設定する

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
*課題が解消されたら該当セクションを削除し、完了済みテーブルに追記すること。*
