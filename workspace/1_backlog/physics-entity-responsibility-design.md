# PhysicsEntity 責務の設計検討

> 作成日: 2026-03-19  
> 参照: [contents-migration-plan.md](../7_done/contents-migration-plan.md) Phase 5, [physics_entity.ex](../../../apps/contents/lib/components/category/physics_entity.ex)  
> 目的: PhysicsEntity の責務範囲を決定する。player_snapshot 注入・player_damaged ハンドリングを共有コンポーネントに持たせるか、AsteroidArena 専用コンポーネントに持たせるかの設計判断を検討する。

---

## 1. 背景

### 1.1 現状の PhysicsEntity の責務

`Contents.Components.Category.PhysicsEntity` は physics_scenes を持つコンテンツ向けのエンティティイベントアダプタとして、以下の 4 つを担っている。

| 責務 | 内容 |
|------|------|
| enemy_damage_this_frame | on_nif_sync で frame_injection に注入。Content の enemy_damage_this_frame/1 に委譲 |
| handle_enemy_killed | on_frame_event で enemy_killed イベント時に Content.handle_enemy_killed/4 を呼ぶ |
| player_snapshot | on_nif_sync で playing_state から player_hp / invincible_until_ms を取得し frame_injection に注入 |
| player_damaged | on_frame_event で player_damaged イベント時に SceneStack 経由で playing_state を更新 |

### 1.2 設計上の論点

- **enemy_damage_this_frame** と **handle_enemy_killed** は、Content コールバックに委譲する形で汎用化されており、AsteroidArena 以外のコンテンツでも再利用可能である。
- **player_snapshot** と **player_damaged** は、VampireSurvivor では LevelComponent が担当している。PhysicsEntity に持たせた場合、責務の二重化や「共有 vs 専用」の境界が曖昧になる。

そのため、以下を検討する必要がある。

- player_snapshot 注入・player_damaged ハンドリングを PhysicsEntity（共有）に持たせるか
- AsteroidArena 専用のコンポーネントに持たせるか

---

## 2. 選択肢

### 2.1 選択肢 A: PhysicsEntity に統一（現状維持）

**方針**: 上記 4 責務をすべて PhysicsEntity に置く。

| メリット | デメリット |
|----------|------------|
| physics_scenes を持つコンテンツ（AsteroidArena 等）が単一コンポーネントで完結 | 責務が多く、コンポーネントが肥大化する |
| VampireSurvivor は LevelComponent で従来通り。コンテンツごとに選択可能 | player 関連ロジックが LevelComponent と PhysicsEntity で重複し、境界が分かりにくい |
| 新規 physics コンテンツは PhysicsEntity を追加するだけで済む | invincible_duration_ms 等の Content コールバックに依存し、汎用性に制約 |

### 2.2 選択肢 B: AsteroidArena 専用コンポーネントに分離

**方針**: player_snapshot と player_damaged を AsteroidArena 専用コンポーネント（例: `Content.AsteroidArena.PhysicsAdapter`）に移す。PhysicsEntity は enemy_damage_this_frame と handle_enemy_killed のみ担当。

| メリット | デメリット |
|----------|------------|
| PhysicsEntity の責務が「敵関連」に絞られ、見通しが良くなる | AsteroidArena のコンポーネント数が増える |
| 共有コンポーネントとコンテンツ固有ロジックの境界が明確になる | player 関連の共通パターンが LevelComponent と専用コンポーネントに分散する |
| 将来の physics コンテンツは player の扱いを自由に設計できる | 同様の player 処理が必要な新規コンテンツで、再度専用コンポーネントを書く可能性 |

### 2.3 選択肢 C: 責務ごとにコンポーネントを分割

**方針**: player_snapshot / player_damaged を扱う共有コンポーネント（例: `Contents.Components.Category.PlayerStateSync`）を新設し、PhysicsEntity から分離する。

| メリット | デメリット |
|----------|------------|
| 責務が細かく分かれ、単一責任の原則に近づく | コンポーネント数が増え、ディスパッチ・テストの複雑さが上がる |
| VampireSurvivor の LevelComponent の player 処理を段階的に移行できる可能性 | LevelComponent と PlayerStateSync の役割分担・移行手順の検討が必要 |
| 他の physics コンテンツでも PlayerStateSync を再利用しやすい | 過度な抽象化になる可能性 |

---

## 3. 検討項目（未決定）

- [ ] **Content.EntityParams と Content.VampireSurvivor.EntityParams の責務分担**  
  boss_params は Content.EntityParams、enemy/weapon は VampireSurvivor.EntityParams にあり混在している。SSoT の観点から VampireSurvivor のパラメータをどこで一元管理するか、方針を整理する余地がある。
- [ ] VampireSurvivor の LevelComponent との関係（重複許容か、将来的に統合するか）
- [ ] 新規 physics コンテンツの想定（player の扱いがどの程度共通化されるか）
- [ ] コンポーネント数の増加と保守性のトレードオフ
- [ ] Phase 5 レビュー指摘を踏まえた「プレイヤー HP 同期が従来通り動作すること」の検証結果

---

## 4. 次のアクション

本ドキュメントは検討用であり、現時点では結論を出さない。  
上記選択肢と検討項目を踏まえ、関係者で議論の上、方針を決定する。  
決定後、本ドキュメントに結論と理由を追記する。
