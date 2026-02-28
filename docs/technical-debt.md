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

---

## 残課題

### 課題 1: `GameEvents.context` のルール固有キー残存

**優先度**: 中（2つ目のコンテンツ着手前に対応推奨）

**問題**: `GameEngine.GameEvents.build_context/3` が組み立てる `context` マップに、
VampireSurvivor 固有の概念が含まれている。

```elixir
# 現状の context（game_events.ex の build_context/3）
%{
  level:        state.level,       # ← Rule 固有
  exp:          state.exp,         # ← Rule 固有
  exp_to_next:  state.exp_to_next, # ← Rule 固有
  boss_hp:      state.boss_hp,     # ← Rule 固有
  boss_max_hp:  state.boss_max_hp, # ← Rule 固有
  boss_kind_id: state.boss_kind_id,# ← Rule 固有
  # ...汎用キー...
}
```

**対応方針**: これらの値は `GameEngine.GameEvents` の `state` から `RuleBehaviour.context_defaults/0`
経由でシーン側に渡す設計に変更する。エンジンの `state` 自体からも `level`・`exp`・`boss_*`
フィールドを除去し、Playing シーンの `state` のみで管理する。

**影響範囲**: `game_events.ex`・各シーン実装・`RuleBehaviour`

---

### 課題 2: `entity_params.rs` のハードコードされたデフォルト値

**優先度**: 高（2つ目のコンテンツを追加する前に必須）

**問題**: `game_simulation/entity_params.rs` の `EntityParamTables::default()` に
VampireSurvivor 専用のパラメータがハードコードされている。
NIF 経由での外部注入構造（`set_entity_params`）は実装済みだが、
デフォルト値として具体的な種別名・数値が残っている。

```rust
// 現状（entity_params.rs）
pub const WEAPON_ID_MAGIC_WAND: u8 = 0;  // ← VampireSurvivor 専用
pub const WEAPON_ID_AXE:        u8 = 1;  // ← VampireSurvivor 専用
// ... 7種の武器定数
// EnemyParams に exp_reward フィールドが存在（Rule 固有の概念）
// WeaponParams・BossParams 構造体が game_simulation に存在
```

**対応方針**:
1. `WEAPON_ID_*`・`BOSS_ID_*`・`ENEMY_ID_*` 定数を `entity_params.rs` から除去
2. `EnemyParams.exp_reward` フィールドを除去（EXP は Elixir 側の `EntityParams` で管理済み）
3. `EntityParamTables::default()` のハードコード値を空テーブルに変更し、
   `set_entity_params` NIF が呼ばれるまで動作しない設計にする
4. `WeaponParams`・`BossParams` 構造体の `name` フィールド等、Rule 固有フィールドを見直す

**影響範囲**: `entity_params.rs`・`weapons.rs`・`boss.rs`（systems）・`game_nif` 全体

---

### 課題 3: `weapons.rs` の武器発射ロジック7種

**優先度**: 高（2つ目のコンテンツを追加する前に必須）

**問題**: `game_simulation/game_logic/systems/weapons.rs` に VampireSurvivor 専用の
7種の武器発射ロジック（`fire_magic_wand`・`fire_axe`・`fire_cross`・`fire_whip`・
`fire_fireball`・`fire_lightning`・`fire_garlic`）がハードコードされている。

```rust
// 現状（weapons.rs）
match kind_id {
    WEAPON_ID_MAGIC_WAND => fire_magic_wand(...),
    WEAPON_ID_AXE        => fire_axe(...),
    // ... 7種
}
```

**対応方針**: 武器発射ロジックを「汎用アタックシステム」に置き換える。
具体的には `WeaponParams` に発射パターン（弾数・角度・追尾有無等）を持たせ、
`fire_*` 関数を汎用の `fire_weapon(params)` 1本に統合する。
または武器発射を完全に Elixir 側に移管し、Rust は弾丸の物理のみを担う設計にする。

**影響範囲**: `weapons.rs`・`entity_params.rs`（WeaponParams）・`game_nif`（NIF 追加が必要）

---

### 課題 4: `GameBehaviour` の完全廃止

**優先度**: 低（現状は `@deprecated` マーク済みで後方互換ラッパーとして機能）

**問題**: `GameEngine.GameBehaviour` が廃止マーク済みだが、まだ参照箇所が残っている可能性がある。
`GameContent.VampireSurvivor` も後方互換ラッパーとして残存している。

**対応方針**:
1. `GameBehaviour` の全参照箇所を `WorldBehaviour`・`RuleBehaviour` に置き換え
2. `GameContent.VampireSurvivor`（後方互換ラッパー）を削除し、
   `VampireSurvivorWorld`・`VampireSurvivorRule` を直接参照する形に移行
3. `game_behaviour.ex` ファイルを削除

**影響範囲**: `game_behaviour.ex`・`vampire_survivor.ex`・参照箇所全体

---

### 課題 5: `FrameEvent` の `boss_*` バリアント

**優先度**: 低（現状は Elixir 側で適切に処理されており動作上の問題はない）

**問題**: `FrameEvent` に `BossDefeated`・`BossSpawn`・`BossDamaged` という
VampireSurvivor 固有の概念が残っている。

**対応方針**: 将来的には `EntityDefeated { entity_kind: u8, x, y }`・
`EntitySpawned { entity_kind: u8 }` 等の汎用バリアントに置き換える。
ただし「ボス」という特殊エンティティの概念がエンジン汎用かどうかは設計判断が必要。

**影響範囲**: `frame_event.rs`・`events.rs`・`game_events.ex`

---

## 2つ目のコンテンツを追加するために必要な最低限の作業

以下が完了していれば、同じ Rust エンジン上で異なるパラメータセットを持つ
2つ目のゲームコンテンツを追加できる。

1. **課題 2 の解消**（`entity_params.rs` のハードコード除去）
   → 別ゲームの敵・武器・ボスパラメータを NIF 経由で注入できるようになる
2. **課題 3 の解消**（武器発射ロジックの汎用化）
   → 別の攻撃パターンを持つ武器を定義できるようになる

課題 1・4・5 は 2つ目のコンテンツ追加後でも対応可能。

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
*課題が解消されたら該当セクションを削除し、完了済みテーブルに追記すること。*
