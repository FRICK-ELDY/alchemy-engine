# GPT 評価 — プラス点詳細一覧

評価日: 2026-08-25 / 評価者: GPT-5.6 Sol  
検証commit: `8f35a57`（PR #347後、CI項目を再検証）

## 採点基準

### プラス点

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装 |
| +2 | 一般的ベストプラクティス |
| +3 | 同種平均を明確に上回る |
| +4 | production OSSと遜色ない |
| +5 | 個人開発として卓越 |

## auth

### Identity基盤

- **RS256 multi-key JWKS** `+5`
  > active/verification鍵、thumbprint kid、duplicate拒否を実装する。
  > 対象ファイル: `../auth/lib/auth/token/keys.ex`
- **refresh rotation + family reuse検知** `+5`
  > grace超過再利用でfamily全失効する。
  > 対象ファイル: `../auth/lib/auth/accounts.ex`
- **Argon2id + timing対策** `+4`
  > user不在でもdummy verifyを実行する。
  > 対象ファイル: `../auth/lib/auth/accounts.ex`
- **多軸rate limit** `+4`
  > IP/identifier/email/token別bucketとtelemetryを持つ。
  > 対象ファイル: `../auth/lib/auth/rate_limit.ex`
- **account lifecycleの完結性** `+5`
  > verify/reset/change/deactivateとcredential変更時失効を実装する。
  > 対象ファイル: `../auth/lib/auth/accounts.ex`
- **失敗分類と列挙耐性** `+4`
  > malformed/expired/revoked/inactiveを閉じ、user不在も同じcredential errorにする。
  > 対象ファイル: `../auth/lib/auth_web/plugs/authenticate.ex`
- **Ash宣言的resource制約** `+4`
  > validation/change/identityをresourceへ集約する。
  > 対象ファイル: `../auth/lib/auth/accounts/user.ex`
- **security-sensitive test群** `+4`
  > JWT/JWKS/rate/lifecycle/cleanupを15 filesで覆う。
  > 対象ファイル: `../auth/test/`
- **TOS版・時刻記録** `+3`
  > version/timestampを永続化する。
  > 対象ファイル: `../auth/lib/auth/accounts/changes/stamp_tos_agreement.ex`
- **prod fail-fast** `+3`
  > secret/DB env欠落をraiseする。
  > 対象ファイル: `../auth/config/runtime.exs`
- **release配布定義** `+3`
  > mix releaseをprojectへ接続する。
  > 対象ファイル: `../auth/mix.exs`
- **trusted proxy IPとtoken cleanup** `+3`
  > forwarded address解決とrevocation/refresh GCを備える。
  > 対象ファイル: `../auth/lib/auth_web/client_ip.ex`

**小計: +47**

## assets

### 所有BLOBサービス

- **JWT subject path ownership** `+4`
  > `users/{sub}/private` 完全prefixとtraversal拒否を実装する。
  > 対象ファイル: `../assets/lib/assets/path_policy.ex`
- **RS256/JWKS claim検証** `+4`
  > kid/signature/iss/aud/sub/jti/status/expを検証する。
  > 対象ファイル: `../assets/lib/assets/token/verifier.ex`
- **size limit付きCRUD** `+3`
  > PUT/GET/DELETE/listと1MiB既定上限を提供する。
  > 対象ファイル: `../assets/lib/assets/objects.ex`
- **Ash metadata + storage behaviour** `+3`
  > owner/path/URI/size/typeとunique path、交換可能adapterを持つ。
  > 対象ファイル: `../assets/lib/assets/inventory/asset_metadata.ex`
- **active Postgres CI** `+2`
  > format/compile/Credo/migrate/testをworkflowで実行する。
  > 対象ファイル: `../assets/.github/workflows/ci.yml`

**小計: +16**

## engine — apps/core

### Formula・OTP

- **FormulaGraph compiler** `+5`
  > topological sortとcycle/port/register検証を行う。
  > 対象ファイル: `apps/core/lib/core/formula_graph.ex`
- **Elixir encoder↔Rust VM契約** `+4`
  > opcodeを一元化しNIF境界へ渡す。
  > 対象ファイル: `apps/core/lib/core/formula.ex`
- **FormulaStore 3 scope + MFA注入** `+4`
  > synced/local/contextとnetwork broadcastの疎結合を実装する。
  > 対象ファイル: `apps/core/lib/core/formula_store.ex`
- **optional Component contract** `+3`
  > 必要callbackだけの実装を許す。
  > 対象ファイル: `apps/core/lib/core/component.ex`
- **権威tick SSoT** `+3`
  > 10/20/30/60 allowlistと20Hz fallbackを持つ。
  > 対象ファイル: `apps/core/lib/core/config.ex`
- **room lifecycle API** `+2`
  > DynamicSupervisor + Registryで重複防止・停止・cleanupを行う。
  > 対象ファイル: `apps/core/lib/core/room_supervisor.ex`
- **FrameCache/Stats汎用化** `+2`
  > room keyとcontent非依存counterへ整理した。
  > 対象ファイル: `apps/core/lib/core/frame_cache.ex`

**小計: +23**

## engine — apps/contents

### ゲームループ・交換性

- **backpressure時の整合性** `+4`
  > state更新を維持しpublish/diagnosticsだけをskipする。
  > 対象ファイル: `apps/contents/lib/events/game.ex`
- **authoritative tick + dt化** `+4`
  > 全roomを駆動し主要contentはcontext dtで進む。
  > 対象ファイル: `apps/contents/lib/events/game.ex`
- **5 contentの交換実証** `+4`
  > Game、3D、UI、Formula、OSCという異なるsurfaceを同じcontractで切替える。
  > 対象ファイル: `apps/contents/lib/contents/`
- **FrameEncoder protobuf一元化** `+3`
  > draw/UI/mesh/audioをwire frameへ集約する。
  > 対象ファイル: `apps/contents/lib/contents/frame_encoder.ex`
- **network MFA疎結合** `+3`
  > compile依存を避けpublishを注入する。
  > 対象ファイル: `apps/contents/lib/events/game.ex`
- **VR/OSC入力境界** `+3`
  > pose/button/trackerをguardし、LittleOSC receiverを実接続する。
  > 対象ファイル: `apps/contents/lib/contents/sample_osc/playing.ex`

**小計: +21**

## engine — apps/network

### Transport・認証・連合

- **3 transportのdomain収束** `+5`
  > Zenoh/UDP/Channelを同じmovement/action messageへ正規化する。
  > 対象ファイル: `apps/network/lib/network/zenoh_bridge.ex`
- **auth↔engine JWKS接続** `+5`
  > alg/kid/iss/aud/exp/statusとkid miss refreshを実装する。
  > 対象ファイル: `apps/network/lib/network/auth_verifier.ex`
- **UDP/Zenoh RoomToken** `+4`
  > JOIN/envelopeを共通検証する。
  > 対象ファイル: `apps/network/lib/network/room_auth.ex`
- **inflate limit + session timeout** `+4`
  > 64KiB streaming limitとmonotonic sweepを持つ。
  > 対象ファイル: `apps/network/lib/network/udp/protocol.ex`
- **署名付きread-only S2S** `+4`
  > JWKS/aud/iss/content filterを検証する。
  > 対象ファイル: `apps/network/test/network_s2s_test.exs`
- **S2S SSRF/rotation防御** `+4`
  > 未登録issuer fetch拒否とunknown kid再取得をtestする。
  > 対象ファイル: `apps/network/test/network_s2s_test.exs`

**小計: +26**

## engine — apps/server

### 起動

- **main room fail-fast** `+2`
  > 予期しない起動失敗をraiseする。
  > 対象ファイル: `apps/server/lib/server/application.ex`
- **test外部依存分離** `+2`
  > Endpoint/Zenohをoff、UDP port 0、broadcast nilにする。
  > 対象ファイル: `config/test.exs`

**小計: +4**

## engine — rust/nif

### Formula VM

- **VM domain error tuple** `+4`
  > 実行時errorをBEAM tupleへ変換する。
  > 対象ファイル: `rust/nif/src/nif/formula_nif.rs`
- **decoder境界検査** `+4`
  > length/register/UTF-8を検査する。
  > 対象ファイル: `rust/nif/src/formula/decode.rs`
- **除算修正 + regression test** `+4`
  > float昇格、checked_div、zero/MINを6 testで固定する。
  > 対象ファイル: `rust/nif/src/formula/vm.rs`

**小計: +12**

## engine — rust/client

### Client architecture

- **10 crate責務分離** `+5`
  > app/audio/auth/network/render/proto/shared/UI/window/xrを分離する。
  > 対象ファイル: `rust/Cargo.toml`
- **Elixir↔Rust golden protobuf E2E** `+5`
  > commands/camera/UI/audioを意味検証する。
  > 対象ファイル: `rust/client/network/tests/render_frame_e2e_contract.rs`
- **OS credential store** `+5`
  > refreshをnative store、accessをmemoryに置く。
  > 対象ファイル: `rust/client/auth_client/src/token_store.rs`
- **snapshot interpolation実配線** `+5`
  > timestamp queue、adaptive delay、playback clampを表示経路で使う。
  > 対象ファイル: `rust/client/network/src/network_render_bridge.rs`
- **Rust Zenoh recovery** `+4`
  > generation、backoff reconnect、subscriber復元を持つ。
  > 対象ファイル: `rust/client/network/src/platform/desktop.rs`
- **publisher cache + lock discipline** `+4`
  > declare/put/waitをstate mutex外で行う。
  > 対象ファイル: `rust/client/network/src/platform/desktop.rs`
- **OpenXR headless loop本体** `+3`
  > session lifecycle/action/pose syncを実装する。
  > 対象ファイル: `rust/client/xr/src/openxr_loop.rs`
- **GPU/audio回復設計** `+3`
  > buffer再利用、surface再構成、no-device fallbackを持つ。
  > 対象ファイル: `rust/client/render/src/renderer/mod.rs`
- **client asset traversal防御** `+3`
  > prefix/`..`/backslashを拒否する。
  > 対象ファイル: `rust/client/audio/src/asset/mod.rs`

**小計: +37**

## 横断評価層

### DX・契約

- **mix alchemy.ci単一入口** `+5`
  > Rust/Elixir gateとfilterを一つのtaskへ統合する。
  > 対象ファイル: `apps/core/lib/mix/tasks/alchemy.ci.ex`
- **proto drift検知設計** `+4`
  > generator pinと再生成diffをworkflowへ定義する。
  > 対象ファイル: `.github/workflows/ci.yml`
- **契約志向test** `+4`
  > UDP実socket、S2S SSRF、protobuf golden等を持つ。
  > 対象ファイル: `apps/network/test/`
- **secret fail-fastと開発導線** `+4`
  > prod envをraiseし、server/router/client/launcher手順を記す。
  > 対象ファイル: `config/runtime.exs`

**小計: +17**

## 横断評価層 — ゲームプレイ完成度

### 遊べるコンテンツ

- **BulletHell3D完結loop** `+4`
  > 入力、spawn、追跡、敵弾、collision、HP、game over、damage audioを実装する。
  > 対象ファイル: `apps/contents/lib/contents/bullet_hell_3d/playing.ex`
- **Tetris完結flow** `+4`
  > title/play/game over/retry、3D盤面、score/line/level、操作UIを持つ。
  > 対象ファイル: `apps/contents/lib/contents/tetris/frame.ex`
- **3 demoと統一描画contract** `+4`
  > Canvas/Formula/OSCがengine能力を実画面で示し、3D/UI/audioを同じframeで運ぶ。
  > 対象ファイル: `apps/contents/lib/contents/`

**小計: +12**

## 総計

### カテゴリ別

| 大分類 | プラス |
|:---|---:|
| auth | +47 |
| assets | +16 |
| apps/core | +23 |
| apps/contents | +21 |
| apps/network | +26 |
| apps/server | +4 |
| rust/nif | +12 |
| rust/client | +37 |
| 横断評価層 | +17 |
| ゲームプレイ完成度 | +12 |
| **合計** | **+215** |
