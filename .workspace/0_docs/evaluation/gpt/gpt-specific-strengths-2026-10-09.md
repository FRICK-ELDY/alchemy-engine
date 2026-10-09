# AlchemyEngine 強み詳細 — GPT-5.6 Sol（2026-10-09）

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている |
| +2 | 一般的ベストプラクティスに沿う |
| +3 | 同規模プロジェクトの平均を明確に上回る |
| +4 | プロダクション級OSSと比べても遜色ない |
| +5 | 個人プロジェクトとして卓越している |

## 技術評価層 — world-server/

### apps/contents

- **コンテンツ差し替え境界が実装で証明されている** `+4`
  > Content behaviour、scene type dispatch、component listにより、Tetris・BulletHell3D・Canvas・Formula・OSCが同じ権威tickに載る。エンジンがゲーム固有scene moduleを直接知らない構造はGodotのNode/Scene分離に近い。
  > 対象ファイル: `world-server/apps/contents/lib/behaviour/content.ex`

- **ゲームルールと描画定義をElixir側に保持する** `+3`
  > BulletHell3Dは移動・敵・弾・HPをElixir管理と明記し、mesh definitionもcontentsから供給する（`bullet_hell_3d.ex:3-16,107-116`）。Rust側へバランス値を埋め込まないSSoT方針がコードに反映されている。
  > 対象ファイル: `world-server/apps/contents/lib/contents/bullet_hell_3d.ex`

- **汎用UI/描画フレームへの収束** `+3`
  > frame encoderとprotobufを通じてscene固有状態をdraw command/UI treeへ変換し、clientは意味を知らず描画する。層間知識を上位に戻す方向性は明確である。
  > 対象ファイル: `world-server/apps/contents/lib/contents/frame_encoder/proto.ex`

### apps/core

- **ルーム単位GenServerとDynamicSupervisorの骨格** `+3`
  > RoomSupervisorはroom_idごとにchild specを作り、停止時にFrameCacheも消す（`room_supervisor.ex:15-47`）。OTPの「失敗単位をプロセス所有単位へ合わせる」設計を採っている。
  > 対象ファイル: `world-server/apps/core/lib/core/room_supervisor.ex`

- **FormulaGraph/Storeの責務分離** `+3`
  > graph compilation、VM呼出し、synced/local/context storeが分かれ、Rustは計算、Elixirは定義・永続化を担当する契約が明記されている（`formula_store.ex:1-35`）。
  > 対象ファイル: `world-server/apps/core/lib/core/formula_store.ex`

- **権威tickのバックプレッシャー設計** `+4`
  > mailbox depthで非critical side effectだけを落とし、ゲーム状態更新と入力処理は維持する（`events/game.ex:327-349,420-444`）。単なるqueue dropではなく「何を保証するか」が実装に現れている。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

### apps/network

- **複数transportをroom eventへ収束する** `+4`
  > Local/Phoenix/UDP/Zenohが最終的にRoomRegistryのイベントhandlerへ入力を渡す。transport固有処理とゲームロジックを分離できている。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`

- **RS256/JWKS検証が厳密** `+4`
  > alg固定、kid、iss/aud/exp/iat/sub/jti/status、clock skew、kid miss再取得を検査する（`auth_verifier.ex:130-227`）。単なる署名確認より一段強く、Phoenix一般アプリの水準を上回る。
  > 対象ファイル: `world-server/apps/network/lib/network/auth_verifier.ex`

- **分散ルームとread-only S2Sを実装まで進めた** `+2`
  > 単一ノードfallbackを保ちながら、remote close/broadcast/listと署名付きworld catalogを備える（`distributed.ex:22-133`, `s2s/client.ex:8-61`）。
  > 対象ファイル: `world-server/apps/network/lib/network/distributed.ex`

### apps/server

- **必須contentと秘密鍵をfail-fastする** `+2`
  > content未設定は起動時raise、prodのSECRET_KEY_BASE未設定もruntime configで停止する（`application.ex:9-17`; `runtime.exs:27-48`）。壊れた設定でサービスを公開しない。
  > 対象ファイル: `world-server/config/runtime.exs`

### rust/nif（physicsを含む）

- **小さく型付きのFormula VMに限定した** `+3`
  > NIFはFormula実行に絞り、64 register、明示opcode、typed Value、saturating arithmeticで責務が狭い（`decode.rs:27-49`; `vm.rs:25-109`）。巨大なゲームworldをResourceArcに抱える旧設計より障害面が小さい。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`

- **算術panic境界を具体的テストで封じた** `+2`
  > mixed/F32 division、zero、`i32::MIN / -1` を6テストで固定し、checked/saturating方針を明記する（`vm.rs:151-167,227-307`）。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`

## 技術評価層 — client/

### shared

- **SnapshotInterpolatorが卓越している** `+5`
  > 適応delay、EMA、burst除外、timeline reset、spawn/despawn、audio一回配送、out-of-order破棄を備え、18テストで時間軸の失敗を固定する（`interp.rs:411-616,619-1102`）。同規模の自作ネットワーククライアントでは稀な完成度である。
  > 対象ファイル: `client/shared/src/interp.rs`

- **描画契約型をrenderから分離した** `+3`
  > Ui tree、camera、mesh、draw commandをsharedが持ち、GPU crateへの依存なしでnetwork/render双方から参照する（`render_frame/mod.rs:1-7,195-208`）。
  > 対象ファイル: `client/shared/src/render_frame/mod.rs`

### network

- **Zenoh再接続とlock外I/O** `+4`
  > generation、single reconnect gate、publisher cache、500ms〜8s backoff、再購読を備え、close/put待機中にstate lockを保持しない（`desktop.rs:20-49,250-376`）。描画stutterと再接続競合を同時に扱っている。
  > 対象ファイル: `client/network/src/platform/desktop.rs`

- **最新フレーム優先とprotobuf契約テスト** `+4`
  > subscriberを容量1のringにして古いframeを配送前に捨てる（`desktop.rs:457-491`）。network E2E contract testも存在し、低遅延ゲーム向けの方針が一貫する。
  > 対象ファイル: `client/network/tests/render_frame_e2e_contract.rs`

### render

- **wgpu 2D instancing・3D・UIの統合** `+4`
  > instance buffer、camera uniform、content supplied WGSL、3D pipeline、eguiを一つのframeに構成する（`renderer/mod.rs:338-469,520-666`）。技術デモを越えて実用的な描画器である。
  > 対象ファイル: `client/render/src/renderer/mod.rs`

- **CI向けoffscreen rendererを持つ** `+3`
  > surfaceなしのadapter/device、row alignment、submission待機、PNG encodeまでResultで返す（`headless.rs:80-129,375-535`）。テスト配線は不足するが、回帰検証の器は良い。
  > 対象ファイル: `client/render/src/headless.rs`

### window

- **入力所有権とメニュー状態を明確に分ける** `+3`
  > ESCはclient system UIが所有し、メニュー中はゲーム入力を遮断、focus lossでheld keysをclearし、server cursor intentへ復帰する（`desktop_loop.rs:91-109,145-200,211-264`）。
  > 対象ファイル: `client/window/src/desktop_loop.rs`

### audio

- **音声を専用threadへ隔離しデバイス不在を許容する** `+3`
  > command patternでゲーム/render threadから分離し、出力deviceがなくてもcommandをdropしてclientを止めない（`audio.rs:65-79,120-179`）。
  > 対象ファイル: `client/audio/src/audio.rs`

### app

- **統合entrypointが薄い** `+2`
  > asset、audio、network bridge、window、system UIを組み立てるだけに留め、各crateの実装詳細をmainへ持ち込まない（`main.rs:23-56`）。
  > 対象ファイル: `client/app/src/main.rs`

## 技術評価層 — auth-server/

### lib/auth

- **refresh token family再利用検知** `+5`
  > tokenはhash保存、rotation、family維持、grace後の再利用でfamily全失効、inactivity expiryを実装する（`accounts.ex:102-133,306-327,338-401`）。一般的なPhoenix生成認証より明確に強い。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **アカウントライフサイクルをtransactionで閉じる** `+4`
  > email verify、password reset、change、deactivateでrow lock/transactionとrefresh失効を組み合わせる（`accounts.ex:156-176,204-273,459-515`）。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **RS256鍵rotationとArgon2id** `+4`
  > active+verification key群、thumbprint kid、JWKS、duplicate kid fail-fast、prod key自動生成禁止を実装し（`keys.ex:53-111`）、passwordはArgon2とdummy verifyを使う（`password.ex:1-35`）。
  > 対象ファイル: `auth-server/lib/auth/token/keys.ex`

### lib/auth_web

- **公開・rate limit・authenticated境界が明快** `+4`
  > Router pipelineが公開auth、保護API、health/JWKSを分ける（`router.ex:3-40`）。Authenticateはfailureを分類しながら外部へ一様な401/403を返す。
  > 対象ファイル: `auth-server/lib/auth_web/router.ex`

- **多軸rate limitと列挙耐性** `+3`
  > login/register/refresh/reset等をIP+identifier/email/token familyで制限し、verification/reset要求は存在有無によらず同じ応答を返す（`rate_limit.ex:11-25`; `auth_controller.ex:152-169`）。
  > 対象ファイル: `auth-server/lib/auth_web/plugs/rate_limit.ex`

## 横断評価層

### テスト戦略

- **wire/security/time軸の重要箇所に焦点がある** `+3`
  > protobuf golden/E2E、JWKS verifier、multi-room tick、distributed/UDP、interpolator、refresh/key testが存在する。単純getterより壊れやすい境界を優先している。
  > 対象ファイル: `world-server/apps/network/test/network/proto/protobuf_contract_test.exs`

### 可観測性・デバッグ容易性

- **認証失敗とrate limitを構造化する** `+2`
  > Authenticateはstatus/code/contextを構造化logにし、RateLimitはtelemetryとstructured warningを出す（`authenticate.ex:151-168`; `rate_limit.ex:90-106`）。
  > 対象ファイル: `auth-server/lib/auth_web/plugs/authenticate.ex`

### エラーハンドリング戦略

- **境界ごとのgraceful degradationがある** `+3`
  > audio device不在、malformed VR input、unknown room、GPU surface lost、JWKS refresh失敗を局所回復または明示errorへ変換する。全面panicよりサービス継続を優先する姿勢は一貫する。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

### 変更容易性・保守性

- **superprojectとprotocol SSoTの分離** `+4`
  > world-server/client/auth/protocolを独立repoにし、ワイヤ契約はprotocol、ドメイン判断はElixirと定義する（`README.md:30-40`; `vision.md:69-83`）。変更所有者が明確である。
  > 対象ファイル: `README.md`

### 開発者体験（DX）

- **子repoごとの警告ゼロCI** `+3`
  > world-serverはfmt/clippy/proto codegen/compile/format/credo/test、authはPostgres service付きprecommit相当を実行する（`world-server/.github/workflows/ci.yml:15-156`; `auth-server/.github/workflows/ci.yml:8-55`）。
  > 対象ファイル: `world-server/.github/workflows/ci.yml`

- **world-serverの単一ローカル入口** `+2`
  > `mix alchemy.ci` はfilter付きでRust/Elixirのformat、lint、testを一つの結果にまとめる（`alchemy.ci.ex:1-53`）。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`

### セキュリティ・配布可能性

- **秘密鍵・鍵ファイルをfail-secureに扱う** `+3`
  > prod SECRET_KEY_BASE欠如で起動を止め、authのJWT private keyも生成禁止時は欠如で停止し、生成時は0600にする（`runtime.exs:27-48`; `keys.ex:101-135`）。
  > 対象ファイル: `auth-server/lib/auth/token/keys.ex`

- **authはrelease可能な単位になっている** `+2`
  > `mix.exs` にrelease定義とprecommit aliasがあり、CIはDB migrationを含めて検証する（`mix.exs:65-94`; `.github/workflows/ci.yml:49-55`）。
  > 対象ファイル: `auth-server/mix.exs`

### プロジェクト全体設計

- **「定義はElixir、表示はRust」が大半のコードで守られる** `+4`
  > contentsがscene/rule/mesh/UIを定義し、clientはprotobuf frameを補間・描画する。Bevy/Godotとは異なるが、権威と体感を分ける独自の一貫した設計である。
  > 対象ファイル: `.workspace/0_docs/vision.md`

- **保証と非保証を文書化する姿勢** `+2`
  > visionはengine/content、authority/display、domain/wire SSoTを明示する（`vision.md:17-37,69-92`）。実装との乖離はあるが、レビュー可能な判断軸を提供している。
  > 対象ファイル: `.workspace/0_docs/vision.md`

**合計: +116点（36項目）**
