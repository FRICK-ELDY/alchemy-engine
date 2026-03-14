# 武器式の Formula 移行評価（P1-2）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P1-2  
> 目的: 武器ダメージ・クールダウン等の式を Formula VM に移行する余地を評価する

---

## 1. 現状の SSoT

| 式 | 所在 | 注入経路 |
|:---|:---|:---|
| effective_damage | `WeaponFormulas.effective_damage/2` (Elixir) | `set_weapon_slots` の `precomputed_damage` |
| effective_cooldown | `WeaponFormulas.effective_cooldown/2` (Elixir) | `set_weapon_slots` の `cooldown_sec` |
| whip_range | Elixir + Rust の entity_params フォールバック | Elixir は `weapon_upgrade_descs`、Rust は `WeaponParams.whip_range` |
| aura_radius | 同上 | 同上 |
| chain_count_for_level | 同上 | 同上 |
| bullet_count | Elixir + Rust の entity_params | テーブル参照。Elixir は `weapon_upgrade_descs`、Rust は `WeaponParams.bullet_count` |

**注**: ダメージ・クールダウンは既に Elixir で計算し、Rust には事前計算済み値を注入している（R-W1, R-W2）。Rust 側で式計算は行っていない。

---

## 2. Formula VM の能力

| 能力 | 可否 |
|:---|:---|
| 四則演算 (add, sub, mul, div) | ✓ |
| 比較 (lt, gt, eq) | ✓ |
| 定数 (i32, f32, bool) | ✓ |
| 入力 (inputs map) | ✓ |
| Store (永続状態の read/write) | ✓ |
| 出力 (outputs list) | ✓ |

| 制約 | 内容 |
|:---|:---|
| 型 | F32, I32, Bool のみ |
| レジスタ数 | 64 |
| 名前長 | 255 バイト以下（LoadInput, ReadStore, WriteStore の name/key） |

**不足機能**:
- `max`, `min`, `clamp` 等の数学関数
- `div` の整数除算（i32 同士では `/` が整数除算として動作）

---

## 3. 各式の Formula 移行可否

### 3.1 effective_damage

```elixir
# 現行: base + (level - 1) * max(base/4, 1)
inc = max(div(base_damage, 4), 1)
base_damage + (lv - 1) * inc
```

| 観点 | 評価 |
|:---|:---|
| Formula で表現可能か | **部分的**。`max` が無いため、`base/4` と `1` の大きい方を取る処理を分岐で表現する必要がある。`lt`/`gt` で条件分岐し、2 つの式の結果を選ぶグラフを組める。 |
| メリット | 式変更時に Elixir の再コンパイル不要。コンテンツごとに異なる式を Formula で定義可能。 |
| デメリット | グラフが複雑になる。現行は 1 関数で簡潔。 |
| 推奨 | **現状維持**。Elixir 関数の方が可読性・メンテナンス性が高い。式の変更頻度が低いため、Formula 化の優先度は低い。 |

### 3.2 effective_cooldown

```elixir
# 現行: base * (1 - (lv-1)*0.07), min = base*0.5
factor = 1.0 - (lv - 1) * 0.07
max(base_cooldown * factor, base_cooldown * 0.5)
```

| 観点 | 評価 |
|:---|:---|
| Formula で表現可能か | **可**。`max` は `gt` で分岐すれば表現可能。 |
| 推奨 | **現状維持**。同上。Elixir 関数で十分。 |

### 3.3 whip_range / aura_radius / chain_count_for_level

```elixir
# whip: base_range + (level - 1) * 20.0
# aura: base_range + (level - 1) * 15.0
# chain: base_chain_count + div(level, 2)
```

| 観点 | 評価 |
|:---|:---|
| Formula で表現可能か | **可**。四則演算のみ。 |
| 推奨 | **現状維持**。これらは **Rust 側の entity_params フォールバック** で使われる。Rust がフォールバック式を持つのが「定義の二重管理」になるため、本来はテーブル未定義時も Elixir から値を渡す設計にすべき。Formula 化より **パラメータ注入の一元化** が優先。 |

### 3.4 bullet_count

テーブル参照。Formula 化には向かない（配列インデックスアクセスが VM にない）。

---

## 4. Formula 化が有効なケース

| ケース | 説明 |
|:---|:---|
| **コンテンツごとに式が異なる** | 例: VampireSurvivor と BulletHell3D で damage 式が違う場合、各コンテンツが FormulaGraph を定義すれば、Rust は共通 VM で実行するだけでよい。 |
| **ランタイムで式を差し替える** | パッチやモードで式を変えたい場合、Elixir でグラフを差し替えてバイトコードを再生成すればよい。 |
| **デバッグ・チューニング** | 式をコード変更せずにパラメータで調整したい場合。ただし現行の WeaponFormulas も引数で調整可能。 |

現状の VampireSurvivor は **単一コンテンツ** で、式も固定。上記メリットは薄い。

---

## 5. 結論と推奨

| 項目 | 推奨 |
|:---|:---|
| effective_damage / effective_cooldown | **現状維持**。Elixir 関数のまま。事前計算して Rust に注入する現行設計で十分。 |
| whip_range / aura_radius / chain_count_for_level | **Rust フォールバック式の削除を検討**。テーブル未定義時は Elixir がデフォルト値を渡すか、必須テーブルとして扱いフォールバックを廃止。Formula 化は不要。 |
| 新規コンテンツで式が増える場合 | 式がコンテンツ固有で複雑になるなら、**そのコンテンツ用の FormulaGraph** を検討。共通化より柔軟性を優先する場合に有効。 |

**サマリ**: 現時点では **武器式の Formula 移行は不要**。SSoT は Elixir にあり、Rust は事前計算値を実行するだけ。移行余地はあるが、投資対効果は低い。代わりに **entity_params の Rust フォールバック式と Elixir の二重定義を解消** する方が「Contents 定義 / Rust 実行」の原則に沿う。

---

## 6. 関連ドキュメント

- [formula-hardcode-inventory.md](./formula-hardcode-inventory.md) — ハードコード一覧（P1-1）
- [formula-vm-bytecode.md](./formula-vm-bytecode.md) — Formula VM バイトコード仕様（P1-3）
- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — 方針・リファクタリング計画
