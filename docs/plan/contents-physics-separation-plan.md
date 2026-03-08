# apps/contents ↔ native/physics 責務分離計画書

> 作成日: 2026-03-08  
> 目的: contents で式を定義し、physics では式の計算・予測・線形補間のみを行う構成を徹底する。

---

## 1. 基準（責務の原則）

### 1.1 ルール

| レイヤー | 責務 | 禁止事項 |
|:---|:---|:---|
| **apps/contents** | 式の定義、ゲームロジック、パラメータの SSoT | 物理演算の実装、高速数値計算 |
| **native/physics** | 式の計算、予測、線形補間 **のみ** | 式の定義、ゲーム定数のハードコード、ロジック分岐の定義 |

### 1.2 physics が許容される処理

1. **式の計算**  
   contents が定義した式（Formula VM または事前計算値）を受け取り、それを適用する。
2. **予測（Dead Reckoning）**  
   ネットワーク遅延補正のための位置予測。
3. **線形補間**  
   描画用のサブフレーム補間（プレイヤー位置等）。

### 1.3 データフロー（目標）

```
contents                           physics
─────────                          ───────
式定義・パラメータ  ──注入──→  [式の計算]
                              [予測・補間]
計算結果・イベント  ←──返却──  衝突検出等の結果
```

---

## 2. 基準不合致の洗い出し

### 2.1 カテゴリ別一覧

| # | カテゴリ | 箇所 | 内容 | 基準違反の種別 |
|:--:|:---|:---|:---|:---|
| 1 | 式の二重定義 | entity_params.rs | whip_range, aura_radius, chain_count のフォールバック式 | physics が式を定義している |
| 2 | 魔法数・定数 | weapons.rs | spread (PI*0.08), whip_half_angle (PI*0.3), エフェクト lifetime | contents 未定義の定数 |
| 3 | パーティクル色 | weapons.rs, projectiles.rs, effects.rs | ヒット時色のハードコード | contents 未定義 |
| 4 | 発射パターン定義 | weapons.rs | dirs_4, dirs_8, bcount>=8 閾値 | 武器挙動の定義が physics にある |
| 5 | パーティクル物理 | effects.rs | 重力 200.0 | contents 未定義 |
| 6 | 衝突クエリ定数 | projectiles.rs | bullet_query_r (BULLET_RADIUS+32), マップ外マージン ±100 | contents 未定義 |
| 7 | デフォルト定数 | entity_params.rs | DEFAULT_*, CHAIN_BOSS_RANGE | contents の SSoT でない |
| 8 | 物理定数 | constants.rs | ENEMY_SEPARATION_*, 各種デフォルト | 注入可能だが未整理 |
| 9 | Chase AI 式 | chase_ai.rs | 「プレイヤー方向へ speed で移動」の式 | 式が physics に固定 |

---

## 3. 洗い出し詳細と対策

### 3.1 entity_params フォールバック式（優先度: 高）

**現状**:  
`WeaponParams::whip_range`, `aura_radius`, `chain_count_for_level` で、テーブル未定義時に Rust 側の式を使用。

```rust
// entity_params.rs L98-124
unwrap_or(self.range + (level as f32 - 1.0) * 20.0)  // whip
unwrap_or(self.range + (level as f32 - 1.0) * 15.0)  // aura
unwrap_or(self.chain_count as usize + level as usize / 2)  // chain
```

**対策**:
- **contents で必須化**: SpawnComponent の weapon_params で `whip_range_per_level`, `aura_radius_per_level`, `chain_count_per_level` を必ず渡す。
- **physics のフォールバック削除**: テーブルが空の場合は panic または 0 を返し、式計算を行わない。
- **式の SSoT**: 既に `WeaponFormulas.whip_range/2` 等で Elixir に式がある。SpawnComponent が全レベル分のテーブルを計算して注入する。

### 3.2 weapons.rs の魔法数（優先度: 高）

| 定数 | 現状値 | 用途 | 対策 |
|:---|:---|:---|:---|
| spread | PI * 0.08 | Aimed 弾の扇状間隔 | WeaponParams に `aimed_spread_rad` を追加、contents から注入 |
| whip_half_angle | PI * 0.3 | Whip 扇形の半角（54°） | WeaponParams に `whip_half_angle_rad` を追加 |
| whip_effect_lifetime | 0.12 | Whip エフェクト表示時間 | WeaponParams に `effect_lifetime_sec` を追加 |
| lightning_effect_lifetime | 0.10 | Lightning エフェクト表示時間 | 同上 |

**対策**:
- `weapon_params` に上記フィールドを追加。
- contents の SpawnComponent / WeaponFormulas で値を定義し、`set_entity_params` で注入。

### 3.3 パーティクル色のハードコード（優先度: 中）

| 箇所 | 色 | 用途 |
|:---|:---|:---|
| weapons.rs | [1.0, 0.6, 0.1, 1.0] | Whip ヒット |
| weapons.rs | [0.3, 0.8, 1.0, 1.0] | Lightning ヒット |
| weapons.rs | [0.9, 0.9, 0.3, 0.6] | Aura ヒット |
| projectiles.rs | [1.0, 0.4, 0.0, 1.0] | 貫通弾ヒット |
| projectiles.rs | [1.0, 0.9, 0.3, 1.0] | 通常弾ヒット |

**対策**:
- `EnemyParams.particle_color` は既に contents から注入済み。敵撃破時はこれを使用。
- 武器別のヒットパーティクル色を `WeaponParams` に追加し、contents で定義。
- または、エフェクト定義を contents に集約し、effect_id を注入。physics は effect_id に応じた色を「テーブル参照」するのみ（テーブルは contents から注入）。

### 3.4 発射パターン（Radial）の定義（優先度: 中）

**現状**:  
`bcount >= 8` で 8 方向、それ以外で 4 方向。方向ベクトルは Rust 内で固定。

**対策**:
- `WeaponParams` に `radial_dirs` または `radial_dir_count` を追加。
- または、level ごとの方向ベクトルリストを contents で計算して注入（フォーマットは要設計）。
- 閾値 `bcount >= 8` は `WeaponFormulas.fire_pattern_extra` と一致しているため、contents で「何発以上で何方向か」を式として定義し、その結果を注入。

### 3.5 パーティクル重力（effects.rs）（優先度: 中）

**現状**:  
`velocities_y[i] += 200.0 * dt` がハードコード。

**対策**:
- `set_world_params` に `particle_gravity` を追加。
- contents の SpawnComponent で `world_params` に定義し注入。

### 3.6 衝突クエリ・マップ外マージン（projectiles.rs）（優先度: 中）

| 定数 | 現状 | 対策 |
|:---|:---|:---|
| bullet_query_r | BULLET_RADIUS + 32.0 | 敵半径上限の仮定。`set_world_params` に `bullet_query_radius` を追加するか、entity_params の最大 radius から導出するよう contents が注入。 |
| マップ外マージン | ±100.0 | `set_world_params` に `map_margin` を追加。 |

### 3.7 デフォルト定数（entity_params.rs）（優先度: 低）

**現状**:  
`DEFAULT_ENEMY_RADIUS`, `DEFAULT_PARTICLE_COLOR`, `DEFAULT_WHIP_RANGE` 等。params にない kind_id 用。

**対策**:
- 原則: contents は全 kind_id の params を必ず渡す。フォールバックは「未定義 = バグ」とする。
- やむを得ずフォールバックが必要な場合は、`set_entity_params` に `default_enemy_radius` 等をオプションで渡す。Rust は「注入されたデフォルト」のみ使用。

### 3.8 CHAIN_BOSS_RANGE（優先度: 中）

**現状**:  
Chain がボスに連鎖する最大距離 600.0 が entity_params.rs にハードコード。

**対策**:
- `set_world_params` または `set_entity_params` に `chain_boss_range` を追加。
- contents で定義して注入。

### 3.9 Chase AI の式（優先度: 検討）

**現状**:  
`chase_ai.rs` で `velocity = normalize(player_pos - enemy_pos) * speed` が固定。

**扱い**:
- この式は「物理シミュレーション」の一部。移動式そのものは単純なベクトル演算。
- **案 A**: 現状維持。speed は params 由来で、式はエンジン共通の「追跡移動」として許容する。
- **案 B**: contents が「移動式」を Formula またはバイトコードで定義し、physics が VM で評価する。オーバーヘッド・複雑さを要検討。
- **推奨**: 案 A。追跡式はエンジン固定とし、speed のみ contents が定義。式の差し替えニーズが高くなったら案 B を検討。

---

## 4. コンテンツ側で完結させる式・定義の整理

### 4.1 既に contents で定義済み（維持）

| 式/定義 | 所在 | 注入経路 |
|:---|:---|:---|
| effective_damage | WeaponFormulas | set_weapon_slots.precomputed_damage |
| effective_cooldown | WeaponFormulas | set_weapon_slots.cooldown_sec |
| whip_range, aura_radius, chain_count | WeaponFormulas + テーブル | whip_range_per_level 等 |
| enemy_params, boss_params | EntityParams, SpawnComponent | set_entity_params |
| world_params | SpawnComponent | set_world_params |
| enemy_damage_this_frame | LevelComponent | set_enemy_damage_this_frame |
| score_from_exp | EntityParams | LevelComponent が使用 |

### 4.2 追加で contents に移す定義

| 定義 | 追加先 | 注入経路 |
|:---|:---|:---|
| aimed_spread_rad | weapon_params | set_entity_params |
| whip_half_angle_rad | weapon_params | set_entity_params |
| effect_lifetime_sec（武器別） | weapon_params | set_entity_params |
| hit_particle_color（武器別） | weapon_params | set_entity_params |
| radial_dir_count（または level→dirs マッピング） | weapon_params | set_entity_params |
| particle_gravity | world_params | set_world_params |
| bullet_query_radius | world_params | set_world_params |
| map_margin | world_params | set_world_params |
| chain_boss_range | world_params | set_world_params |

### 4.3 式の参照例（contents 内で完結）

```elixir
# SpawnComponent - weapon_params に追加する例
defp weapon_params_impl do
  [
    # Magic Wand (Aimed)
    %{
      # ...
      aimed_spread_rad: :math.pi() * 0.08,
      effect_lifetime_sec: 0.12,
      hit_particle_color: [1.0, 0.6, 0.1, 1.0]
    },
    # Whip
    %{
      # ...
      whip_half_angle_rad: :math.pi() * 0.3,
      effect_lifetime_sec: 0.12,
      hit_particle_color: [1.0, 0.6, 0.1, 1.0]
    },
    # ...
  ]
end

# world_params に追加
defp world_params do
  Map.merge(default_world_params(), %{
    particle_gravity: 200.0,
    bullet_query_radius: 6.0 + 32.0,  # BULLET_RADIUS + max_enemy_radius
    map_margin: 100.0,
    chain_boss_range: 600.0
  })
end
```

---

## 5. native/physics の制約強化

### 5.1 削除する処理

- `WeaponParams` の `whip_range`, `aura_radius`, `chain_count_for_level` 内のフォールバック式
- 各システム内の魔法数（上記対策で注入に置き換え）
- `CHAIN_BOSS_RANGE` 等の定数（注入に置き換え）

### 5.2 許容する処理（変更なし）

- 式の適用: 注入された値を使った位置更新・ダメージ適用
- 空間クエリ: Spatial Hash による最近接探索・衝突判定
- 線形補間: プレイヤー位置の lerp
- 予測: 将来的な Dead Reckoning

### 5.3 チェックリスト（実装時の確認）

- [ ] 新しい定数を physics に追加する前に、contents での定義可否を検討する
- [ ] 「未定義時のフォールバック」は持たない。contents が必ず値を渡す設計にする
- [ ] パーティクル色・エフェクトパラメータはすべて注入

---

## 6. フェーズ別実施計画

### Phase 1: 高優先度（1〜2 週間）

| タスク | 内容 | 影響ファイル |
|:---|:---|:---|
| P1-1 | whip/aura/chain フォールバック式の削除 | entity_params.rs |
| P1-2 | SpawnComponent で全 weapon に whip_range_per_level 等を必ず渡す | spawn_component.ex |
| P1-3 | aimed_spread_rad, whip_half_angle_rad を weapon_params に追加 | spawn_component.ex, entity_params.rs, weapons.rs |
| P1-4 | effect_lifetime_sec を weapon_params に追加 | 同上 |

### Phase 2: 中優先度（1〜2 週間）

| タスク | 内容 | 影響ファイル |
|:---|:---|:---|
| P2-1 | hit_particle_color を weapon_params に追加 | spawn_component.ex, weapons.rs, projectiles.rs |
| P2-2 | particle_gravity を world_params に追加 | spawn_component.ex, effects.rs |
| P2-3 | bullet_query_radius, map_margin, chain_boss_range を world_params に追加 | spawn_component.ex, projectiles.rs, entity_params.rs |

### Phase 3: Radial パターン（必要に応じて）

| タスク | 内容 | 影響ファイル |
|:---|:---|:---|
| P3-1 | radial_dir_count または dirs テーブルを weapon_params に追加 | spawn_component.ex, weapons.rs |

### Phase 4: デフォルト値の整理（低優先度）

| タスク | 内容 | 影響ファイル |
|:---|:---|:---|
| P4-1 | set_entity_params にオプションの default_* を追加（必要な場合のみ） | nif, entity_params.rs |

---

## 7. 関連ドキュメント

- [contents-defines-rust-executes.md](./contents-defines-rust-executes.md) — 定義 vs 実行の方針
- [formula-hardcode-inventory.md](../architecture/formula-hardcode-inventory.md) — ハードコード一覧
- [formula-migration-evaluation.md](../architecture/formula-migration-evaluation.md) — 武器式の移行評価
- [client-server-separation-procedure.md](./client-server-separation-procedure.md) — 定義の SSoT 化（Phase 0）
