# AsteroidArena コンテンツ仕様

## 概要

武器・ボス・レベルアップの概念を持たないシンプルなシューター。`Content.AsteroidArena` モジュール。エンジンがゲーム固有概念を持たなくても動作することを実証する設計です。

---

## コンポーネント構成

```elixir
def components do
  [
    Content.AsteroidArena.SpawnComponent,  # ワールド初期化・エンティティ登録
    Content.AsteroidArena.SplitComponent   # 小惑星分裂処理
  ]
end
```

---

## 特徴

- `level_up_scene/0` / `boss_alert_scene/0` を実装しない（ContentBehaviour のオプショナルコールバック）
- 小惑星の分裂処理: Large → Medium × 2 → Small × 2
- シーン構成: **Playing** / **GameOver** のみ

---

## SpawnComponent

ワールド初期化・エンティティ登録。VampireSurvivor と同様に `on_ready/1` でマップサイズ・エンティティパラメータを注入。

---

## SplitComponent

小惑星撃破時の分裂処理を担当。`on_frame_event/2` で敵撃破イベントを受け、大型・中型の小惑星を分割してスポーン。

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
