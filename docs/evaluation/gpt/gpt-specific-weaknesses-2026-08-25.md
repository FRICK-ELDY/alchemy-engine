# GPT 評価 — マイナス点詳細一覧

評価日: 2026-08-25 / 評価者: GPT-5.6 Sol  
検証commit: `8f35a57`（PR #347後、CI項目を再検証）

## 採点基準

### マイナス点

| 点数 | 基準 |
|:---:|:---|
| -1 | 軽微な改善余地 |
| -2 | 重要な機能・設計の欠如 |
| -3 | バグ・性能劣化を起こしうる明確な欠陥 |
| -4 | 価値命題を損なう重大な欠如 |
| -5 | 根幹を揺るがす致命的欠陥 |

## プロジェクト全体

### アーキテクチャ・運用

- **CI再無効化を防ぐ強制力なし** `-2`
  > HEADはgreenかつ有効だが、enable/ignore反復履歴がありrequired checks/branch protectionがない。
  > 対象ファイル: `.github/workflows/ci.yml`
- **評価ルールと保証文書が旧構成** `-4`
  > `.cursor/rules/evaluation.mdc:48-99` は旧構成、`docs/warranty/ci.md:10-13,46` は削除済みphysicsとCredo 15を記すが実値は10。
  > 対象ファイル: `docs/warranty/ci.md`
- **連合がread-only catalog止まり** `-2`
  > identity federation、visit、state同期、moderationは未実装。
  > 対象ファイル: `apps/network/lib/network/s2s/catalog.ex`
- **engine永続化が未成立** `-3`
  > FormulaStoreはETS寿命で、新assets serviceもengineから未使用。
  > 対象ファイル: `apps/core/lib/core/formula_store.ex`

**小計: -11**

## auth

### アカウント・運用

- **メール未検証でもJWT発行** `-2`
  > `auth/lib/auth/accounts.ex:57-67` は `email_verified_at` を検査しない。
  > 対象ファイル: `../auth/lib/auth/accounts.ex`
- **最低年齢policyなし** `-1`
  > birthday validationは過去日のみを要求する。
  > 対象ファイル: `../auth/lib/auth/accounts/validations/birthday_in_past.ex`
- **healthにDB readinessなし** `-1`
  > 固定statusだけを返す。
  > 対象ファイル: `../auth/lib/auth_web/controllers/health_controller.ex`
- **AccountToken GCが不完全** `-1`
  > 検証/reset tokenを包括しない。
  > 対象ファイル: `../auth/lib/auth/token_cleanup.ex`
- **rate limitが単一node ETS** `-1`
  > 水平scale時に実効上限がnode数倍になる。
  > 対象ファイル: `../auth/lib/auth/rate_limit.ex`
- **CORS allowlistなし** `-1`
  > 拒否既定のorigin policyがない。
  > 対象ファイル: `../auth/lib/auth_web/endpoint.ex`
- **Dialyzer/依存監査なし** `-1`
  > CIはformat/compile/credo/testまで。
  > 対象ファイル: `../auth/.github/workflows/ci.yml`

**小計: -8**

## assets

### 永続BLOBサービス

- **engine save/load未配線** `-4`
  > README自身がengine `__save__` / `__load__` を後続Phaseと明記する（`assets/README.md:155-160`）。
  > 対象ファイル: `../assets/README.md`
- **BLOBとmetadataが非atomic** `-3`
  > `assets/lib/assets/objects.ex:22-26,47-53` はfile操作とAsh action間をrollbackできない。
  > 対象ファイル: `../assets/lib/assets/objects.ex`
- **12 testはfailure/concurrencyを覆わない** `-2`
  > 同path同時PUT、DB失敗、disk full、不整合reconcileがない。
  > 対象ファイル: `../assets/test/`
- **local disk単一adapter** `-1`
  > node local filesystemであり水平scaleできない。
  > 対象ファイル: `../assets/lib/assets/storage/local.ex`

**小計: -10**

## engine — apps/core

### OTP・契約

- **room別Gameとglobal stateful childが不整合** `-3`
  > SceneStack/EventBus/Statsはserver起動時に1個だけである。
  > 対象ファイル: `apps/server/lib/server/application.ex`
- **NifBridge Behaviour未配線・型不一致** `-2`
  > Formulaは実NIF直呼びで、Behaviourのstore型も実契約と一致しない。
  > 対象ファイル: `apps/core/lib/core/nif_bridge_behaviour.ex`
- **FormulaStore ETSがOTP非所有** `-2`
  > 初回callerがnamed ETSをlazy作成する。
  > 対象ファイル: `apps/core/lib/core/formula_store.ex`
- **Component文書が旧60Hz/NIF world前提** `-1`
  > 現行Elixir権威tickと一致しない。
  > 対象ファイル: `apps/core/lib/core/component.ex`

**小計: -8**

## engine — apps/contents

### World・Rule

- **全roomが単一SceneStackを共有** `-5`
  > `flow_runner(_room_id)` が常に同じregistered processを返す。
  > 対象ファイル: `apps/contents/lib/contents/bullet_hell_3d.ex`
- **状態分離test不足** `-2`
  > multi-room testはframe_count増加しか見ない。
  > 対象ファイル: `apps/contents/test/events/game_multi_room_tick_test.exs`
- **Tetrisだけ固定60Hz** `-3`
  > `tetris/playing.ex:10,40-42` はcontextを無視して1/60秒進める。
  > 対象ファイル: `apps/contents/lib/contents/tetris/playing.ex`
- **Object親子APIがstub** `-2`
  > childのparentをnilにする。
  > 対象ファイル: `apps/contents/lib/objects/core/create_empty_child.ex`
- **descriptor実行系がstub** `-2`
  > ContentLoaderは現状stubと明記する。
  > 対象ファイル: `apps/contents/lib/contents/content_loader.ex`
- **撤去済みframe injectionをhot loopに温存** `-1`
  > 毎tick Process dictionaryを初期化する。
  > 対象ファイル: `apps/contents/lib/events/game.ex`

**小計: -15**

## engine — apps/network

### 認証・transport

- **AUTH_REQUIREDがprodでも既定false** `-3`
  > 環境変数漏れで全入口が匿名になる。
  > 対象ファイル: `config/runtime.exs`
- **Elixir ZenohBridgeに再接続なし** `-4`
  > initで1回openし、publish失敗はlogのみ（`zenoh_bridge.ex:52-84,112-133`）。
  > 対象ファイル: `apps/network/lib/network/zenoh_bridge.ex`
- **RoomTokenがJWT subjectに未束縛** `-3`
  > routerはclaimsを捨てroom_idだけを署名する。
  > 対象ファイル: `apps/network/lib/network/router.ex`
- **UDP seq/replay/fragmentation契約なし** `-4`
  > sessionはlast_seenだけで、RenderFrame全体を単一datagramへ載せる。
  > 対象ファイル: `apps/network/lib/network/udp/server.ex`
- **room所在解決が全node RPC scan** `-2`
  > 呼出しごとに全nodeのroom listを走査する。
  > 対象ファイル: `apps/network/lib/network/distributed.ex`
- **S2S clientが平文HTTP許容** `-1`
  > localhost外HTTPSを強制しない。
  > 対象ファイル: `apps/network/lib/network/s2s/client.ex`
**小計: -17**

## engine — apps/server

### 起動・配布

- **専用testゼロ** `-1`
  > application起動/設定失敗を直接検証しない。
  > 対象ファイル: `apps/server/lib/server/application.ex`
- **engine release定義なし** `-2`
  > `mix run --no-halt` 前提でservice/container artifactがない。
  > 対象ファイル: `mix.exs`

**小計: -3**

## engine — rust/nif

### Formula VM

- **通常scheduler NIFにsize/gas上限なし** `-3`
  > user bytecode/input/store量を制限しない。
  > 対象ファイル: `rust/nif/src/nif/formula_nif.rs`
- **decode error契約が非対称** `-3`
  > inputs/storeとerror種類によりtupleとNIF exceptionが混在する。
  > 対象ファイル: `rust/nif/src/nif/formula_nif.rs`
- **Rust 6 testがDIV偏重** `-1`
  > decoder、全opcode、storeを覆わない。
  > 対象ファイル: `rust/nif/src/formula/vm.rs`

**小計: -7**

## engine — rust/client

### 統合・表示

- **OpenXRが出荷appへ未配線** `-4`
  > default featureが空でappも有効化しない。
  > 対象ファイル: `rust/client/app/Cargo.toml`
- **client testがCI対象外** `-3`
  > CIは `cargo test -p nif` のみ。
  > 対象ファイル: `apps/core/lib/mix/tasks/alchemy.ci.ex`
- **補間対応がstable IDでなく最近傍** `-3`
  > 密集弾で誤対応/O(n²)となる。
  > 対象ファイル: `rust/client/shared/src/interp.rs`
- **network crateがrender/audioへ依存** `-2`
  > transportが具体表示層へ逆依存する。
  > 対象ファイル: `rust/client/network/Cargo.toml`
- **WASM transportがstub** `-2`
  > 常に未実装error/空thread。
  > 対象ファイル: `rust/client/network/src/platform/web.rs`
- **render回帰testゼロ** `-2`
  > golden image/device smokeがない。
  > 対象ファイル: `rust/client/render/src/headless.rs`
- **culling/SE voice limitなし** `-2`
  > SEごとにSinkを生成し、visibility stageもない。
  > 対象ファイル: `rust/client/audio/src/audio.rs`
- **RenderFrame clone負荷** `-1`
  > UI/mesh clone蓄積が残る。
  > 対象ファイル: `rust/client/shared/src/interp.rs`

**小計: -19**

## 横断評価層

### 品質・運用

- **property/fuzz/benchmarkなし** `-2`
  > VM/UDP/protobufの生成検証がない。
  > 対象ファイル: `rust/Cargo.toml`
- **telemetryがConsole止まり** `-2`
  > exporter/SLOがなくcontent語彙も残る。
  > 対象ファイル: `apps/core/lib/core/telemetry.ex`
- **dependency auditなし** `-2`
  > engine/auth/assets CIにcargo/Hex監査がない。
  > 対象ファイル: `.github/workflows/ci.yml`
- **platform matrix/署名配布なし** `-2`
  > Ubuntu以外のbuild/installer/SBOMがない。
  > 対象ファイル: `.github/workflows/ci.yml`
- **README・contract drift** `-3`
  > CI、physics、JWT TTL、asset生成説明が現行と食い違う。
  > 対象ファイル: `README.md`

**小計: -11**

## 横断評価層 — ゲームプレイ完成度

### 遊べるゲームとして

- **実ゲームは2本、残り3本は技術demo** `-3`
  > CanvasTest/FormulaTest/SampleOscは機能可視化である。
  > 対象ファイル: `apps/contents/lib/contents/`
- **視覚assetが極薄** `-3`
  > audio 6件とatlas 1件のみで、game別2 directoryは `.gitkeep` だけ。
  > 対象ファイル: `assets/README.md`
- **gameplay E2E / visual regressionなし** `-2`
  > title→play→game over→retryをclient込みで通すtestがない。
  > 対象ファイル: `apps/contents/test/`
- **BulletHell3Dの遊び幅がprototype級** `-2`
  > 単一arena、primitive、基本spawn/collision中心でboss/item/buildがない。
  > 対象ファイル: `apps/contents/lib/contents/bullet_hell_3d/playing.ex`

**小計: -10**

## 総計

### カテゴリ別

| 大分類 | マイナス |
|:---|---:|
| プロジェクト全体 | -11 |
| auth | -8 |
| assets | -10 |
| apps/core | -8 |
| apps/contents | -15 |
| apps/network | -17 |
| apps/server | -3 |
| rust/nif | -7 |
| rust/client | -19 |
| 横断評価層 | -11 |
| ゲームプレイ完成度 | -10 |
| **合計** | **-119** |
