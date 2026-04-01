# AsteroidArena コンテンツ仕様

> **アーカイブ（2026-04）**: `Content.AsteroidArena` はリポジトリから削除済み。以下は旧仕様の記録。

## 概要

武器・ボス・レベルアップの概念を持たないシンプルなシューター。`Content.AsteroidArena` モジュール。エンジンがゲーム固有概念を持たなくても動作することを実証する設計です。

---

## コンポーネント構成

```elixir
def components do
  [
    Contents.Components.Category.Spawner,       # ワールド初期化・エンティティ登録
    Contents.Components.Category.PhysicsEntity  # 物理エンティティ・分裂処理（Playing に埋め込み）
  ]
end
```

---

## 特徴

- `level_up_scene/0` / `boss_alert_scene/0` を実装しない（Contents.Behaviour.Content のオプショナルコールバック）
- 小惑星の分裂処理: Large → Medium × 2 → Small × 2
- シーン構成: **Playing** / **GameOver** のみ

---

## Spawner（Contents.Components.Category.Spawner）

ワールド初期化・エンティティ登録。VampireSurvivor と同様に `on_ready/1` でマップサイズ・エンティティパラメータを注入。

---

## PhysicsEntity（Contents.Components.Category.PhysicsEntity）

物理エンティティ管理。小惑星撃破時の分裂処理は Playing シーン内に埋め込み。

- **Large** → Medium × 2
- **Medium** → Small × 2
- **Small** → 分裂なし（消滅のみ）

---

## シーン構成

- **Playing** — メインゲームプレイ
- **GameOver** — スコア表示・リトライ

VampireSurvivor の LevelUp / BossAlert に相当するシーンはありません。

---

## 関連ドキュメント

- [contents 概要](../contents.md)
- [contents 概要](../contents.md)
- [VampireSurvivor 仕様](./vampire_survivor.md)
