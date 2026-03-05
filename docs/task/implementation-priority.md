# 実装優先度 — Mermaid 図

> 最終更新: 2026-03-05  
> 参照: [docs/plan/](../plan/)、[improvement-plan.md](./improvement-plan.md)

---

## 全体優先度マップ（改善課題・設計タスク）

```mermaid
flowchart TB
    subgraph P1["P1: 高（早期着手）"]
        IB["I-B: spawn_elite_enemy スロットロジック"]
        IC["I-C: PlayerDamaged u32 オーバーフロー"]
        IE["I-E: network 実装"]
        IG["I-G: WebSocket 認証・認可"]
        I18["課題18: render のコンテンツ固有概念"]
    end

    subgraph P2["P2: 中（計画に沿って着手）"]
        ID["I-D: x86_64 cfg pub use 漏れ"]
        IF["I-F: Elixir テスト整備"]
        IH["I-H: EntityParams SSoT 化"]
        II["I-I: CI pull_request トリガー"]
        IL["I-L: render_frame_nif.rs 肥大化"]
        P10["課題10: Elixir の真価"]
        P13["課題13: コンポーネントのシーン直接参照"]
        P14["課題14: セーブ対象データ収集責務"]
        P17["課題17: Diagnostics のコンテンツ固有知識"]
    end

    subgraph P3["P3: 低（余力で着手）"]
        IJ["I-J: build_instances 重複解消"]
        IK["I-K: Skeleton/Ghost スプライト"]
        P9["課題9: クラウドセーブ"]
        P15["課題15: create_world NifResult ラップ"]
    end

    IE --> IG
    IE --> P10
    P10 --> P9
```

---

## 依存関係と推奨実施順序

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: 基盤の安定化"]
        IB["I-B: spawn_elite_enemy"]
        IC["I-C: PlayerDamaged"]
    end

    subgraph Phase2["Phase 2: ネットワーク・セキュリティ"]
        IE["I-E: network"]
        IG["I-G: WebSocket 認証"]
    end

    subgraph Phase3["Phase 3: アーキテクチャ整理"]
        IH["I-H: EntityParams SSoT"]
        IM["I-M: renderer パラメータを contents へ"]
        I18["課題18: render 汎用化"]
        IL["I-L: render_frame_nif 分割"]
    end

    subgraph Phase4["Phase 4: テスト・CI強化"]
        IF["I-F: Elixir テスト"]
        II["I-I: CI PR トリガー"]
    end

    Phase1 --> Phase2
    Phase1 --> Phase4
    Phase2 --> Phase3
```

---

## 計画ドキュメント別の優先度整理

### improvement-plan.md の課題

| ID | 課題 | 優先度 | Phase |
|:---|:---|:---:|:---:|
| I-D | x86_64 cfg pub use 漏れ | 中 | 4 |
| I-E | network 実装 | 高 | 2 |
| I-F | Elixir テスト整備 | 中 | 4 |
| I-G | WebSocket 認証・認可 | 高 | 2 |
| I-H | EntityParams SSoT 化 | 中 | 3 |
| I-I | CI pull_request トリガー | 中 | 4 |
| I-L | render_frame_nif.rs 肥大化 | 中 | 3 |
| I-M | renderer のゲーム固有パラメータを contents へ移行 | 中 | 3 |

### docs/plan 設計タスクの依存関係

```mermaid
flowchart TB
    subgraph Asset["アセット設計"]
        A1["A-1: AssetLoader URI 対応"]
        A15["A-1.5: .alchemypackage"]
        A2["A-2: Elixir URI 統一"]
        A3["A-3: game_assets 分離"]
        A4["A-4: Ash 統合"]
    end

    subgraph Upper["上位レイヤー基盤"]
        U1["Phase1: インスタンスレジストリ"]
        U2["Phase2: 認証"]
        U3["Phase3: ディスカバリ"]
        U4["Phase4: インスタンス移行"]
    end

    subgraph Formula["数式エンジン"]
        F1["Phase1: 最小実行エンジン"]
        F2["Phase2: Store/Local"]
        F3["Phase3: グラフビルダー"]
    end

    subgraph Storage["アセットストレージ"]
        S1["Phase1: 認証基盤"]
        S2["Phase2: User/Group CRUD"]
        S3["Phase3: AssetMetadata CRUD"]
    end

    A1 --> A15 --> A2 --> A3
    A3 --> A4
    U1 --> U2 --> U3 --> U4
    IE["I-E: network"] --> U2
    IE --> S1
```

---

## 実施順序サマリ（推奨）

1. **I-B, I-C** → バグ・安全性の即時対応
2. **I-E, I-G** → network と認証（Elixir の価値証明）
3. **I-F, I-I** → テスト・CI の強化
4. **I-H, I-L, 課題18** → アーキテクチャの汎用化・保守性向上
5. **A-1〜A-3** → アセット配信基盤（並行検討可）
6. **Upper Phase 1〜2** → インスタンスレジストリ・認証（network 後）
