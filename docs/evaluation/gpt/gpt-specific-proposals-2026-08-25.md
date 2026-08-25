# GPT 評価 — 提案（0点）詳細一覧

評価日: 2026-08-25 / 評価者: GPT-5.6 Sol  
検証commit: `8f35a57`（PR #347後、CI項目を再検証）

## 採点基準

### 提案点

| 点数 | 基準 |
|:---:|:---|
| 0 | 未実装だが、実装すれば価値を高める次のステップ |

## 連合・永続化

### 次のvertical slice

- **訪問可能な連合world** `0`
  > read-only catalogへ署名visit grantとguest identityを追加する。
  > 対象ファイル: `apps/network/lib/network/s2s/instance.ex`
- **world/avatar/asset所有model** `0`
  > owner instance、revision、content hash、moderation statusを永続化する。
  > 対象ファイル: `workspace/0_reference/`
- **engine save/loadからassetsへ最小配線** `0`
  > Tetris/BulletHellの1 slotをschema_version付きJSONとしてPUT/GETする。
  > 対象ファイル: `../assets/lib/assets_web/controllers/object_controller.ex`
- **BLOB/metadata saga + reconciler** `0`
  > temp write→metadata commit→atomic renameとorphan照合を導入する。
  > 対象ファイル: `../assets/lib/assets/objects.ex`
- **OIDC discovery + PKCE** `0`
  > authを標準IdPとしてlauncher/web/他instanceから利用する。
  > 対象ファイル: `../auth/lib/auth/token/keys.ex`

## Formula・Content

### 安全性と交換性

- **Formula gas/capability sandbox** `0`
  > step上限、store key、外部作用capabilityを導入する。
  > 対象ファイル: `rust/nif/src/formula/vm.rs`
- **Elixir reference VM differential test** `0`
  > 生成graphをRust結果とproperty比較する。
  > 対象ファイル: `apps/core/lib/core/formula_graph.ex`
- **content package manifest** `0`
  > engine/proto version、asset hash、permissionをload前検証する。
  > 対象ファイル: `apps/contents/lib/behaviour/content.ex`

## ゲームプレイ

### Prototypeから作品へ

- **BulletHell3Dを15分遊べる1作品へ磨く** `0`
  > wave/boss/item/build/meta progression、専用asset、saveを追加する。
  > 対象ファイル: `apps/contents/lib/contents/bullet_hell_3d/playing.ex`
- **headless gameplay scenario test** `0`
  > seed付き入力でtitle→play→game over→retry、score/frame hash/audioを検証する。
  > 対象ファイル: `apps/contents/test/`
- **game別asset pipeline** `0`
  > source/license/atlas manifestを持つ再現可能な生成・packagingへ置換する。
  > 対象ファイル: `assets/README.md`

## Client・運用

### 出荷品質

- **OpenXR conformance smoke** `0`
  > dummy runtimeでREADY→pose/button→network encodeをCI検証する。
  > 対象ファイル: `rust/client/xr/src/openxr_loop.rs`
- **stable entity ID補間** `0`
  > 最近傍scanをentity_id HashMap joinへ置換する。
  > 対象ファイル: `rust/client/shared/src/interp.rs`
- **headless golden image matrix** `0`
  > 代表2D/3D/UI sceneをimage diffへ接続する。
  > 対象ファイル: `rust/client/render/src/headless.rs`
- **OpenTelemetry room SLO** `0`
  > tick→encode→Zenoh→decode→renderへcorrelation IDを通す。
  > 対象ファイル: `apps/core/lib/core/telemetry.ex`
- **deterministic replay + impairment CI** `0`
  > seed/inputを保存しloss/reorder/jitter下のstate/frame hashを比較する。
  > 対象ファイル: `apps/contents/lib/events/game.ex`
- **QUIC/WebTransport spike** `0`
  > 自前UDP信頼性層を増やす前に比較する。
  > 対象ファイル: `apps/network/lib/network/udp/protocol.ex`
- **reproducible release channel** `0`
  > mix release、署名installer、SBOM、checksumを一つのmanifestへ束ねる。
  > 対象ファイル: `rust/client/app/Cargo.toml`
- **継続benchmark budget** `0`
  > Formula、FrameEncoder、UDP、補間をtick/frame budget比で測る。
  > 対象ファイル: `apps/contents/lib/contents/frame_encoder.ex`

## 総計

### 件数

提案は **19件、0点**。
