# Formula 以外のパラメータ計算 — Rust 側ハードコード一覧（P1-1）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P1-1  
> 目的: Formula 以外のパラメータ計算で Rust 側に残るハードコードを洗い出し、「Elixir 定義 → Rust 実行」の徹底余地を把握する

---

## 1. 概要

Formula は既に「Elixir 定義 → Rust VM 実行」が実現済み。本一覧は **Formula を使っていない** パラメータ計算・式のハードコードを列挙する。

---

## 2. entity_params.rs のハードコード

| 箇所 | 定数/式 | 用途 | Formula 移行の余地 |
|:---|:---|:---|:---|
| 12-27 | `DEFAULT_ENEMY_RADIUS` (16.0) | 敵 kind_id が params にないときの半径 | デフォルト値。params の SSoT を維持すれば移行不要 |
| 15 | `DEFAULT_PARTICLE_COLOR` [1.0, 0.5, 0.1, 1.0] | 敵が params にないときのパーティクル色 | 同上 |
| 18 | `DEFAULT_WHIP_RANGE` (200.0) | Whip 武器が params にないときの範囲 | 同上 |
| 21 | `DEFAULT_AURA_RADIUS` (150.0) | Aura 武器が params にないときの半径 | 同上 |
| 24 | `DEFAULT_CHAIN_COUNT` (1) | Chain 武器が params にないときの連鎖数 | 同上 |
| 27 | `CHAIN_BOSS_RANGE` (600.0) | Chain がボスに連鎖する最大距離 | コンテンツ固有。Elixir 定義化の余地あり |
| 98-104 | `range + (level - 1) * 20.0` | whip_range のフォールバック式 | WeaponFormulas と二重定義。テーブル優先で移行済みだが、未定義時は Rust 側式が使われる |
| 106-114 | `range + (level - 1) * 15.0` | aura_radius のフォールバック式 | 同上 |
| 118-124 | `chain_count + level / 2` | chain_count_for_level のフォールバック式 | 同上 |
| 88-94 | `bullet_table[index] or 1` | bullet_count（level 1-based） | テーブル参照。未定義時 1 は定数で問題なし |

---

## 3. weapon.rs のハードコード

| 箇所 | 定数/式 | 用途 | Formula 移行の余地 |
|:---|:---|:---|:---|
| 9 | `MAX_WEAPON_LEVEL` (8) | 武器レベル上限 | WeaponFormulas と同期が必要。Elixir が SSoT なら Rust は境界チェック用に残す |
| 10 | `MAX_WEAPON_SLOTS` (6) | 武器スロット数 | UI/ゲーム設計。contents が定義、Rust はバッファサイズの検証に使用 |

**注**: `cooldown_sec` と `precomputed_damage` は Elixir の WeaponFormulas で事前計算して注入済み（R-W1, R-W2）。Rust 側で式計算は行っていない。

---

## 4. weapons.rs（発射ロジック）のハードコード

| 箇所 | 定数/式 | 用途 | Formula 移行の余地 |
|:---|:---|:---|:---|
| 86 | `PI * 0.08` | Aimed 弾の扇状 spread（約 4.5° × 弾数間隔） | 武器パラメータ化の余地あり |
| 156 | `PI * 0.3` | Whip の扇角 half-angle（108° の半分 = 54°） | 同上 |
| 159 | `0.12` | Whip エフェクトの lifetime（秒） | エフェクトパラメータ。contents 定義の余地 |
| 214, 306, 355 | `0.10` | Lightning エフェクトの lifetime | 同上 |
| 79, 202, 411 | `[1.0, 0.6, 0.1, 1.0]`, `[0.3, 0.8, 1.0, 1.0]`, `[0.9, 0.9, 0.3, 0.6]` | ヒット時のパーティクル色 | 武器/エフェクト別の色。contents 定義の余地 |
| 114-126 | `dirs_4`, `dirs_8` | Radial 発射方向（4方向/8方向） | 武器種別で固定。bcount>=8 で 8方向に切り替え。パラメータ化の余地 |
| 175 | `bcount <= 3` → 4方向, それ以外 → 8方向 | Radial の方向数切り替え閾値 | WeaponFormulas の fire_pattern_extra と一致。二重定義の可能性 |

---

## 5. projectiles.rs のハードコード

| 箇所 | 定数/式 | 用途 | Formula 移行の余地 |
|:---|:---|:---|:---|
| 35 | `BULLET_RADIUS + 32.0` | 弾丸 vs 敵の衝突クエリ半径 | 敵半径の上限仮定。params 由来なら 32 は過剰かも |
| 29 | `±100.0` | マップ外判定のマージン | 物理定数。set_world_params で注入の余地 |
| 79-81 | `[1.0, 0.4, 0.0, 1.0]`, `[1.0, 0.9, 0.3, 1.0]` | 貫通弾/通常弾のヒットパーティクル色 | 同上 |

---

## 6. collision.rs / 他 systems のハードコード

| ファイル | 箇所 | 定数/式 | 用途 |
|:---|:---|:---|:---|
| collision.rs | - | `DEFAULT_ENEMY_RADIUS` | 敵半径のフォールバック |
| special_entity_collision.rs | - | `BULLET_RADIUS`, `PLAYER_RADIUS` | 衝突半径（constants 由来） |
| spawn.rs | - | `PLAYER_RADIUS` | スポーン位置計算 |
| obstacle_resolve.rs | - | `PLAYER_RADIUS` | 障害物押し出し |

---

## 7. constants.rs のハードコード（物理定数）

| 定数 | 値 | 用途 | 注 |
|:---|:---|:---|:---|
| `PLAYER_SPEED` | 200.0 | プレイヤー移動速度 | set_world_params で注入可能（R-C1） |
| `BULLET_SPEED` | 400.0 | 弾速 | 同上 |
| `BULLET_LIFETIME` | 3.0 | 弾の生存時間 | 同上 |
| `BULLET_RADIUS` | 6.0 | 弾の衝突半径 | 同上の余地 |
| `WEAPON_SEARCH_RADIUS` | SCREEN_WIDTH/2 | 武器の最近接敵探索半径 | 同上 |
| `MAX_ENEMIES` | 300 | 敵上限・Chain の hit_set サイズ | メモリ割り当てに直結。慎重に |
| `ENEMY_RADIUS` | 20.0 | デフォルト敵半径 | 旧定数。entity_params の DEFAULT と重複の可能性 |

---

## 8. 優先度別サマリ

| 優先度 | カテゴリ | 移行推奨 |
|:---:|:---|:---|
| 高 | entity_params の whip/aura/chain フォールバック式 | テーブル未定義時も Elixir から式 or デフォルトを注入する設計に統一 |
| 高 | weapons.rs の spread・扇角・エフェクト lifetime | 武器パラメータ or エフェクト定義に移行 |
| 中 | パーティクル色のハードコード | contents のエフェクト定義へ |
| 中 | CHAIN_BOSS_RANGE | set_entity_params や set_world_params にキー追加 |
| 低 | デフォルト値（DEFAULT_*） | params の SSoT が保証されていれば現状維持で可 |
| 低 | constants の物理定数 | 既に set_world_params で注入可能なものは現状維持 |

---

## 9. 関連ドキュメント

- [formula-migration-evaluation.md](./formula-migration-evaluation.md) — 武器式の Formula 移行評価（P1-2）
- [formula-vm-bytecode.md](./formula-vm-bytecode.md) — Formula VM バイトコード仕様（P1-3）
- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — 方針・リファクタリング計画
