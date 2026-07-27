# バックログ: 権威 tick 仕事量の見える化（Phoenix デバッグ UI）

> 作成日: 2026-07-23  
> ステータス: 未整理（優先度は別途。デバッグ・性能根拠づくり向け）  
> 目的: 権威 tick（推奨 20Hz）の **1 tick 仕事量**を、開発時に Phoenix 経由で可視化し、Hz 選定・ボトルネック判断の根拠にする。

[← README](./README.md)

---

## 1. 背景

主時間は Elixir 権威 tick（推奨 **20Hz**、設定で 10/30/非推奨 60）。  
「何 Hz が安定か」は Hz 単体ではなく、**1 tick の仕事量**で決まる。

見える化したい代表指標:

| 指標 | 意味 |
|:---|:---|
| **エンティティ数** | 敵・弾・プレイヤー等（コンテンツ依存の内訳があるとよい） |
| **DrawCommand 件数** | 描画意図リストの長さ（RenderFrame 組み立て負荷の代理） |
| **protobuf サイズ** | `FrameEncoder` 後のバイト数（帯域・エンコード／デコード負荷） |
| （推奨追加）tick 間隔・処理時間 | 実間隔 vs 目標、encode/publish 所要 |
| （推奨追加）mailbox 深度・drop | 既存バックプレッシャーとの相関 |

Elixir / Phoenix を既に持つため、**デバッグ時は Phoenix で見られる**ようにする（本番必須ダッシュボードではない）。

正本の tick 方針: [authoritative-state-sync-policy.md](../../docs/architecture/authoritative-state-sync-policy.md)

---

## 2. 現状（断片はある）

| 部品 | 現状 | ギャップ |
|:---|:---|:---|
| `Contents.Events.Game.Diagnostics` | 約 60 フレームごとに enemy/bullet 等を `FrameCache` へ | DrawCommand 数・protobuf サイズなし。`physics_ms` は `@tick_ms` 固定値寄り |
| `Core.FrameCache` | ETS 単一スナップショット（`:main` 前提に近い） | ルーム別なし。スキーマが BulletHell 寄り |
| `Core.StressMonitor` | FrameCache を参照して監視 | UI ではなくログ／内部向け |
| `Core.Telemetry` | `game.tick.*` / `frame_dropped` 等 | ConsoleReporter 中心。LiveDashboard 連携・仕事量メトリクス不足。旧 physics 表現が残る |
| `Network.Endpoint`（Phoenix） | Channels / HTTP あり | **tick 仕事量用のデバッグ画面は未整備** |

---

## 3. 方針

### 3.1 デバッグ専用（第一目標）

- **dev / 明示フラグ**でのみ有効（本番デフォルト OFF）  
- Phoenix で閲覧（候補は次のいずれか、または併用）  
  - **LiveDashboard** カスタムページ / メトリクス表示  
  - 簡易 **LiveView**（ルーム選択・時系列・最新スナップショット）  
  - JSON API（`GET /debug/tick_stats`）＋最小 HTML  
- 観測は **権威 tick 経路**にフック（`Events.Game` / `FrameEncoder` / publish 直後）

### 3.2 計測ポイント（案）

権威 tick 1 回あたり:

1. シーン更新後の **エンティティ内訳**（汎用キー + コンテンツ任意）  
2. DrawCommand 組み立て直後の **件数**（タグ別カウントがあるとなお良い）  
3. `encode_frame` 後の **iodata/binary byte_size**  
4. （任意）encode 所要 ms、Zenoh publish 所要 ms  
5. （任意）`Process.info(self(), :message_queue_len)`、drop 有無  

`:telemetry.execute/3` に載せ、UI は Telemetry または ETS リングバッファを読む。

### 3.3 表示の最低ライン（受け入れイメージ）

デバッグ UI で少なくとも次が見える:

- 現在の権威 tick 設定（目標 Hz）と **実測間隔**（直近）  
- 直近 N tick の **entity 数 / DrawCommand 数 / protobuf bytes**（数値＋簡易グラフまたはテーブル）  
- ルーム ID（`:main` 以外も将来対応できる形。初期は `:main` のみ可）

---

## 4. スコープ外（初期）

- 本番向け SLO ダッシュボード・アラート運用の完成形  
- クライアント側 wgpu の GPU 時間（別課題）  
- 隣の Rust sim の内部ステップ詳細（[colocated-rust-physics-sim-design.md](./colocated-rust-physics-sim-design.md) 実装後に拡張）

---

## 5. 段階案

| 段階 | 内容 |
|:---|:---|
| **P0** | `FrameEncoder` / publish 経路で **command_count・byte_size** を Telemetry または FrameCache 拡張に載せる |
| **P1** | Phoenix デバッグページ（LiveDashboard または LiveView）で最新値＋直近履歴を表示 |
| **P2** | エンティティ内訳の汎用化、ルーム別、tick 間隔ヒストグラム |
| **P3** | 負荷試験プロファイル（10/20/30Hz）切替と並べて「推奨 20Hz」の根拠メモを残せるようにする |

---

## 6. `2_todo` 化の受け入れ条件（案）

- [ ] 計測フックの置き場（モジュール・イベント名）を決める  
- [ ] Phoenix UI の形態を 1 つ選ぶ（LiveDashboard / LiveView / JSON+HTML）  
- [ ] dev 限定の有効化方法（config / 環境変数）  
- [ ] 最低 3 指標（entity・DrawCommand・protobuf size）の定義と単位  

---

## 7. 関連ドキュメント

| 文書 | 関係 |
|:---|:---|
| [authoritative-state-sync-policy.md](../../docs/architecture/authoritative-state-sync-policy.md) | 主時間・Hz |
| [authoritative-state-sync-policy-gaps.md](./authoritative-state-sync-policy-gaps.md) | tick 設定化・観測ギャップ |
| [network-scalability-priority-issues.md](./network-scalability-priority-issues.md) | ネットワーク観測の優先課題 |
| [scale-and-gaps.md](../../docs/policy-as-code/gaps/scale-and-gaps.md) | スケール未整備 |
| [colocated-rust-physics-sim-design.md](./colocated-rust-physics-sim-design.md) | 将来 sim 側メトリクス拡張の受け皿 |

---

## 改訂履歴

| 日付 | 内容 |
|:---|:---|
| 2026-07-23 | 初版。tick 仕事量の Phoenix デバッグ可視化を backlog 化 |
