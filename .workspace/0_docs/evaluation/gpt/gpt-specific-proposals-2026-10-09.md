# AlchemyEngine 発展提案 — GPT-5.6 Sol（2026-10-09）

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点の欠点ではないが、実装すれば価値を高める提案 |

## 技術評価層 — world-server/

### apps/contents

- **Content manifest とhot reload transaction** `0`
  > component schema、asset/protocol version、migrationをmanifest化し、検証→shadow起動→frame境界swap→rollbackでランタイム編集を成立させる。GodotのPackedScene importに相当する再現可能な単位になる。
  > 対象ファイル: `world-server/apps/contents/lib/behaviour/content.ex`

### apps/core

- **決定論的tick journal/replay** `0`
  > room_id、tick、入力、content version、seedをappend-only journalへ記録し、障害再現とstate復元を同じ仕組みにする。OTP restart後の保証を監査可能にできる。
  > 対象ファイル: `world-server/apps/core/lib/core/room_supervisor.ex`

### apps/network

- **配置tableと訪問tokenによる連合slice** `0`
  > read-only catalogの次に、instance署名付きvisitor tokenをRoomToken `sub`へ交換する一本を通す。配置tableはbroadcast routingとfederation discoveryの双方に使える。
  > 対象ファイル: `world-server/apps/network/lib/network/s2s/client.ex`

### apps/server

- **room admission controller** `0`
  > memory/tick budget、content allowlist、最大room数を確認してからroom subtreeを起動する。Kubernetes admissionのように「起動できる」と「受け入れてよい」を分ける。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

### rust/nif（physicsを含む）

- **Formula differential oracle** `0`
  > 小さな純Elixir参照interpreterを用意し、proptest生成bytecodeでRust VMと結果比較する。ABI、浮動小数、overflowの回帰をNIF境界込みで検出できる。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`

## 技術評価層 — client/

### shared

- **座標origin rebasing契約** `0`
  > authorityはf64 global coordinate、frameはlocal origin+f32 offsetと明示し、広大空間の精度とGPU効率を両立する。origin versionをframeに持たせ補間跨ぎを禁止する。
  > 対象ファイル: `client/shared/src/render_frame/mod.rs`

### network

- **ネットワーク障害scenario harness** `0`
  > loss/reorder/duplication/jitter/burst/zenohd restartを決定論的に注入し、delay・再接続時間・古いframe表示をbudget assertionする。
  > 対象ファイル: `client/network/src/network_render_bridge.rs`

### render

- **RenderGraphとGPU timestamp budget** `0`
  > 2D/3D/UI passを依存graph化し、timestamp queryで各passのp50/p95をCI artifactへ出す。Bevy RenderGraphほど大規模にせず、pass追加時の影響を可視化する。
  > 対象ファイル: `client/render/src/renderer/mod.rs`

### window

- **入力action mapping asset** `0`
  > physical keyを直接送らず、rebind可能なaction map、device hotplug、gamepad/touch/XRを同じ正規化イベントへ収束させる。
  > 対象ファイル: `client/window/src/desktop_loop.rs`

### audio

- **audio mixer graph** `0`
  > BGM/UI/SE/voice bus、ducking、spatial emitter、limiterをcontent定義可能なgraphとして持つ。単発Sinkから拡張してもゲームルールをclientへ持ち込まずに済む。
  > 対象ファイル: `client/audio/src/audio.rs`

### app

- **接続state machineの型化** `0`
  > LoggedOut→Authenticated→RoomTokenReady→Connecting→InRoom→Reconnectingをenumで表し、UIとtransportを同じ状態から駆動する。認証・再接続・room切替の競合を防げる。
  > 対象ファイル: `client/app/src/main.rs`

## 技術評価層 — auth-server/

### lib/auth

- **WebAuthn/passkey追加** `0`
  > password/refresh familyを維持したままcredential resourceを追加し、phishing耐性のあるprimaryまたはstep-up authを提供する。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

### lib/auth_web

- **OIDC discovery互換のmetadata** `0`
  > JWKSだけでなくissuer、token lifetime、supported alg、API audienceをwell-known metadataとして公開し、world-server/client設定の手入力を減らす。
  > 対象ファイル: `auth-server/lib/auth_web/router.ex`

## 横断評価層

### テスト戦略

- **保証別test matrix** `0`
  > 「room隔離」「identity伝播」「protocol互換」「tick非依存」「精度」の保証ごとにunit/contract/E2E/chaosを対応付け、未検証保証をCI summaryへ出す。
  > 対象ファイル: `.workspace/0_docs/warranty/ci.md`

### 可観測性・デバッグ容易性

- **room trace とclient debug HUD** `0`
  > tick→encode→publish→receive→sample→GPU presentをtrace id/tick idでつなぎ、client HUDにRTT、interp delay、queue、FPS、audio dropsを表示する。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

### エラーハンドリング戦略

- **error taxonomy ADR** `0`
  > retryable/degraded/fatal/programmer errorを全言語共通コードへ整理し、どのSupervisor/threadが回復するかを表にする。NIF tuple、Elixir Result、Rust Resultを同じ意味へ揃えられる。
  > 対象ファイル: `.workspace/0_docs/architecture/overview.md`

### 変更容易性・保守性

- **architecture boundary test** `0`
  > dependency graphをCIで抽出し、contents→network直依存、render→game語彙、core→content module参照をdeny listで落とす。人手レビューだけでなく境界を実行可能にする。
  > 対象ファイル: `world-server/mix.exs`

### 開発者体験（DX）

- **superproject doctor command** `0`
  > submodule pin、Elixir/OTP/Rust/protoc/zenohd、ports、keys、DBを一括診断し、修正コマンドを表示する。Quick Start失敗を環境差とコード不具合に切り分けやすくする。
  > 対象ファイル: `README.md`

### セキュリティ・配布可能性

- **再現可能releaseとprovenance** `0`
  > world-server OCI、client 3OS installer、SBOM、cosign/SLSA provenance、protocol pinを同じrelease tagで公開する。連合運営者が検証可能な配布物を得られる。
  > 対象ファイル: `README.md`

### プロジェクト全体設計

- **最小vertical sliceを製品指標にする** `0`
  > 「新規登録→検証→ログイン→Hub一覧→room参加→編集→他client反映→再接続→保存」を唯一のtop-level acceptance testにし、各repoの完成度ではなく体験の閉じ方を測る。
  > 対象ファイル: `.workspace/0_docs/vision.md`

**合計: 0点（20項目）**
