# Fable 評価 — プラス点詳細一覧

評価日: 2026-07-07 / 評価者: Fable 5（ソースベース評価、ドキュメント非参照）
対象: `auth/`（認証サービス、lib 37 ファイル）+ `engine/`（apps 4アプリ + rust/client 10クレート + rust/nif）
前回評価: 2026-07-04（`archive/2026-07-04/`）。本版は auth 強化（`auth/.workspace/3_done`）を反映した再評価。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSSと比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## auth（認証サービス）

### トークン・暗号設計

- **RS256 非対称 JWT + マルチ鍵 JWKS** `+5`
  > active 鍵で署名し、`jwt_verification_key_paths` で旧鍵を JWKS に併載。`Token.verify/1` は header の `kid` で `signer_for_kid/1` を解決（`token.ex:38-39`, `keys.ex:54-72`）。duplicate kid は起動時 fail-fast。連合型アーキテクチャの鍵ローテーション猶予に対応。
  > 対象ファイル: `auth/lib/auth/token/keys.ex`, `auth/lib/auth/token.ex`

- **Argon2id + 体系的なタイミング攻撃対策** `+4`
  > パスワードは `Argon2.hash_pwd_salt/1`（`password.ex:11`）。ユーザー不在・ハッシュ不正時は必ず `no_user_verify`（`accounts.ex:71-72`）。ログインエラーは常に同一メッセージ。
  > 対象ファイル: `auth/lib/auth/password.ex`, `auth/lib/auth/accounts.ex`

- **リフレッシュトークンのローテーション + family 再利用検知** `+5`
  > `family_id` 単位で毎 refresh 時に rotate（`accounts.ex:354-357`）。失効済みトークンの grace 期間（10秒）超過後の再利用で family 全失効（`accounts.ex:119-124`）。OAuth 2.0 Security BCP に沿った設計で、テストで grace 内外を検証済み。
  > 対象ファイル: `auth/lib/auth/accounts.ex`, `auth/test/auth/accounts_test.exs`

- **jti 失効 + verify 時のユーザー状態再確認** `+3`
  > 失効テーブル照会と DB からの `:active` 再確認。`:deleted` は `:unauthorized`、`:suspended` は `:forbidden` に分岐（`token.ex:97-110`）。
  > 対象ファイル: `auth/lib/auth/token.ex`

- **JWT TTL 15 分** `+1`
  > `jwt_ttl_seconds: 900`（`config.exs:16`）。外部 JWKS 検証者への失効伝播がない設計のリスクを、短 TTL で実用的に緩和。
  > 対象ファイル: `auth/config/config.exs`

### セキュリティ・レート制限

- **多軸レート制限（ETS + 429 + Retry-After）** `+4`
  > `Auth.RateLimit` GenServer が endpoint 別に IP / identifier / email / token family で制限（`rate_limit.ex`, `plugs/rate_limit.ex`）。throttle 時に `[:auth, :rate_limit, :throttle]` telemetry と構造化ログ。prod は env で各 limit を上書き可能（`runtime.exs:141-214`）。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`, `auth/lib/auth_web/plugs/rate_limit.ex`

- **Authenticate プラグの防御深度** `+3`
  > `classify_failure/1` で Joken 構造体エラー・期限切れ・revocation DB 障害を分類し、すべて 401/403 に正規化。`rescue` と未知結果のキャッチオールも実装（`authenticate.ex:41-129`）。malformed/expired/tampered/deleted user の統合テストあり。
  > 対象ファイル: `auth/lib/auth_web/plugs/authenticate.ex`

- **列挙安全な応答設計** `+2`
  > register の uniqueness conflict → 汎用 `:register_failed`（`accounts.ex:37-41`）。forgot-password / resend-verification は存在しなくても同一メッセージ（`accounts.ex:179-200`）。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **ClientIp + trusted proxies** `+2`
  > `remote_ip` による `X-Forwarded-For` 解決。`TRUSTED_PROXIES` env でプロキシ背後の IP 制限を正確化（`client_ip.ex`, `runtime.exs:125-132`）。
  > 対象ファイル: `auth/lib/auth_web/client_ip.ex`

### アカウントライフサイクル

- **メール検証フロー** `+3`
  > 登録時に検証メール送信、`AccountToken`（SHA-256 ハッシュ保存）で verify/resend。`FOR UPDATE` ロック + consume でワンタイム使用（`accounts.ex:459-487`）。
  > 対象ファイル: `auth/lib/auth/accounts.ex`, `auth/lib/auth/accounts/account_token.ex`

- **パスワードリセット・変更・退会 API** `+4`
  > `/api/v1/auth/forgot-password`, `reset-password`, `change-password`, `deactivate` を実装。reset/change 時に全 refresh token 失効（`accounts.ex:215, 244`）。
  > 対象ファイル: `auth/lib/auth_web/router.ex`, `auth/lib/auth/accounts.ex`

### ドメイン・データ設計

- **Ash リソースによる多層バリデーション** `+3`
  > username/email/password/TOS/birthday を宣言的に定義。`BirthdayInPast` で未来日を拒否（`user.ex:86-127`）。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

- **TOS 同意の時刻・バージョン永久記録** `+3`
  > `StampTosAgreement` change が同意時刻と `tos_version` を書き込む。
  > 対象ファイル: `auth/lib/auth/accounts/changes/stamp_tos_agreement.ex`

### 運用・テスト・配布

- **TokenCleanup 定期 GC** `+2`
  > 期限切れ `token_revocations` と stale `refresh_tokens` を定期削除（`token_cleanup.ex`）。grace 日数を config で管理。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **prod secrets + DB SSL の fail-fast** `+2`
  > `SECRET_KEY_BASE` / `DATABASE_URL` 未設定時は raise。`DATABASE_SSL` / `DATABASE_SSL_CA_CERT` で SSL 接続（`runtime.exs`）。
  > 対象ファイル: `auth/config/runtime.exs`

- **CI 品質ゲート + precommit** `+2`
  > GitHub Actions: format / compile --warnings-as-errors / credo --strict / test。`mix precommit` エイリアスあり（`ci.yml`, `mix.exs:87-93`）。
  > 対象ファイル: `auth/.github/workflows/ci.yml`, `auth/mix.exs`

- **本番 release + multi-stage Dockerfile** `+3`
  > `mix release` 定義、`Dockerfile` の build/release ステージ分離、`force_ssl`（health 除外）、`MailConfig` で Postmark/Sendgrid/Mailgun/SMTP 対応。
  > 対象ファイル: `auth/Dockerfile`, `auth/mix.exs`, `auth/lib/auth/mail_config.ex`

- **テスト品質の大幅拡充** `+4`
  > テストファイル 6 → 21。rate limit、lifecycle、token cleanup、multi-key JWKS、authenticate 401 網羅、refresh family reuse をカバー。
  > 対象ファイル: `auth/test/`

- **Ash エラーの構造化 HTTP 整形** `+1`
  > `collect_field_errors/2` がフィールド別 map に再帰変換。
  > 対象ファイル: `auth/lib/auth_web/controllers/auth_controller.ex`

**auth プラス小計: +52**

---

## engine — apps/core

### Formula エンジン

- **FormulaGraph コンパイラ（グラフ→バイトコード）** `+4`
  > Kahn 法トポロジカルソートで循環検出（`formula_graph.ex:151-191`）、ノード・ポート検証、producer ノードへのレジスタ割当（64 上限チェック、`formula_graph.ex:194-201`）を経てバイトコードへコンパイル。ProtoFlux/Logix 風ビジュアルスクリプティングの実行基盤として成立しており、テストも循環・未知 op・missing input を網羅。
  > 対象ファイル: `engine/apps/core/lib/core/formula_graph.ex`

- **Formula バイトコード契約（Elixir エンコーダ ↔ Rust VM）** `+4`
  > opcode 0-13 のバイナリ契約が Elixir 側 `encode_instruction/1`（`formula.ex:79-128`）と Rust 側 `OpCode::from_u8`（`rust/nif/src/formula/opcode.rs`）で完全同期。エラーは `{:error, reason_atom, detail}` の 3 要素タプルに統一され、両言語間の責務分離（コンパイル=Elixir、実行=Rust、永続化=Elixir）が明確。
  > 対象ファイル: `engine/apps/core/lib/core/formula.ex`

- **FormulaStore の 3 スコープ + MFA 疎結合ブロードキャスト** `+3`
  > synced / local / context の 3 スコープを分離し、synced 更新のネットワーク伝播は `config :core, :formula_store_broadcast, {Network.Distributed, :broadcast, []}` の MFA 注入で実現。core が network をコンパイル時依存しない疎結合設計。
  > 対象ファイル: `engine/apps/core/lib/core/formula_store.ex`, `engine/config/config.exs`

### エンジン抽象

- **Core.Component ビヘイビア（7 個の optional callback）** `+3`
  > `on_ready/on_process/on_physics_process/on_event/on_frame_event/on_nif_sync/on_engine_message` を全て optional にし、コンポーネントは必要なものだけ実装（`component.ex:54-70`）。エンジン↔コンテンツ境界が契約として明文化されている。
  > 対象ファイル: `engine/apps/core/lib/core/component.ex`

- **RoomSupervisor + Registry によるマルチルーム基盤** `+2`
  > DynamicSupervisor `:one_for_one` でルーム単位のプロセス分離。`game_events_module` を config 注入しており、core はゲーム実装を知らない。
  > 対象ファイル: `engine/apps/core/lib/core/room_supervisor.ex`

- **StressMonitor の独立プロセス設計** `+2`
  > 性能監視をゲームループから分離した GenServer とし、「クラッシュしてもゲームは継続する」と設計意図を明記。フレームバジェット超過を warning レベルで昇格ログ。
  > 対象ファイル: `engine/apps/core/lib/core/stress_monitor.ex`

- **EventBus の monitor による購読者クリーンアップ** `+1`
  > `Process.monitor` + `:DOWN` で死んだ購読者を自動除去（`event_bus.ex:25-42`）。
  > 対象ファイル: `engine/apps/core/lib/core/event_bus.ex`

**core プラス小計: +19**

---

## engine — apps/contents

### ゲームループ・耐障害設計

- **バックプレッシャー設計（メールボックス深度 + 副作用分離）** `+4`
  > `message_queue_len > 120` でフレームドロップし telemetry 発火（`events/game.ex:313-331`）。throttled 時も「ゲーム整合性に関わる処理（スコア・HP）」は維持し、Zenoh publish・診断キャッシュ等の重い副作用のみスキップ（`game.ex:432-434`）。ドロップと整合性維持を区別する設計は商用ゲームサーバ水準。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **VR 入力のガード + malformed フォールバック** `+2`
  > head_pose / controller_pose / tracker_pose をタプルサイズ・型ガードで検証し、不正ペイロードは警告ログのみでクラッシュ回避（`game.ex:189-268`）。外部入力境界の防御として正しい。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

### コンテンツシステム

- **コンテンツ差し替えアーキテクチャ** `+3`
  > `config :server, :current` の切り替えだけで BulletHell3D / Tetris / CanvasTest / FormulaTest の 4 コンテンツが同一エンジンで動作。`Contents.ComponentList` が LocalUser・Telemetry コンポーネントを自動注入し、シーンスタック（push/pop/replace）も共通化。「コンテンツ交換可能性」を 4 実装で実証している。
  > 対象ファイル: `engine/apps/contents/lib/contents/component_list.ex`, `engine/apps/contents/lib/scenes/stack.ex`

- **FrameEncoder による protobuf 描画パイプライン** `+3`
  > DrawCommand 群（box_3d/cone_3d/sphere_3d/skybox/grid 等）を型別モジュールに分離し、Elixir 側ゲーム状態から protobuf RenderFrame への変換を一元化。Rust クライアントとの golden 契約テストの Elixir 側起点。
  > 対象ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **BulletHell3D のパラメータ外部化と doc honesty** `+2`
  > 難易度テーブル・速度・半径等をモジュール属性に集約（`bullet_hell_3d/playing.ex:39-67`）。「敵のメッシュは円錐だが当たり判定は円近似で、見た目と当たりは一致しない」と制約を moduledoc に明記する誠実さも良い。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/playing.ex`

- **LocalUserComponent による入力統合** `+2`
  > raw_key（クライアント直送）と move_input（ネットワーク経由）を単一コンポーネントに集約し、移動の SSoT を ETS で管理。
  > 対象ファイル: `engine/apps/contents/lib/contents/local_user_component.ex`

- **Nodes / Structs の型体系** `+2`
  > boolean/bool_vectors/operators/flow/time のノード群と value 型（byte〜ulong、color、guid 等）を体系的に整備。ビジュアルスクリプティングの語彙としての将来性がある。
  > 対象ファイル: `engine/apps/contents/lib/nodes/`, `engine/apps/contents/lib/structs/`

**contents プラス小計: +18**

---

## engine — apps/network

- **3 トランスポートの統一メッセージ収束** `+4`
  > Phoenix WebSocket / UDP / Zenoh の 3 経路すべてが `{:move_input, dx, dy}` / `{:ui_action, name}` という同一メッセージに正規化されてゲームループへ届く。トランスポートの追加・交換がゲームロジックに影響しない構造で、同規模プロジェクトでは稀有。
  > 対象ファイル: `engine/apps/network/lib/network/channel.ex`, `engine/apps/network/lib/network/udp/server.ex`, `engine/apps/network/lib/network/zenoh_bridge.ex`

- **RoomToken によるスコープ付き WebSocket 認証** `+3`
  > `Phoenix.Token` で room_id をペイロードに署名し、期限 5 分 + join 時に room スコープ一致を検証（`room_token.ex:65-76`）。エラー種別（missing/expired/invalid/scope_mismatch）ごとに明確な応答を返す。
  > 対象ファイル: `engine/apps/network/lib/network/room_token.ex`

- **ZenohBridge の DoS 防御** `+3`
  > `safe_to_string/1` で map 等を拒否して `to_string` クラッシュ DoS を防止（攻撃シナリオをコメントに明記、`zenoh_bridge.ex:396-408`）、client_info の room_id 正規表現検証 + 最大 100 ルーム制限（`zenoh_bridge.ex:263-314`）。外部入力への脅威モデリングが実装に反映されている。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **OTP ルーム隔離の実証テスト** `+3`
  > `Process.exit(pid_a, :kill)` 後に他ルームの生存と broadcast 継続を assert する統合テストがあり、「ルーム間クラッシュ分離」が口先でなくテストで担保されている。
  > 対象ファイル: `engine/apps/network/test/network_local_test.exs`

- **protobuf 契約テスト（Elixir 側）** `+3`
  > oneof 網羅テスト・契約テストで生成コードのドリフトを検出。CI の proto-verify ジョブと合わせて二重の防護。
  > 対象ファイル: `engine/apps/network/test/network/proto/protobuf_contract_test.exs`

- **UDP プロトコルの文書化と不正パケット耐性** `+2`
  > パケット形式・種別表を moduledoc に明文化し、不正バイナリ送信後もサーバが応答継続することをテストで検証。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`, `engine/apps/network/test/network_udp_test.exs`

- **Distributed の単一ノードフォールバック** `+2`
  > `Node.list() == []` なら `Network.Local` に委譲し、クラスタ未形成でも同一 API で動作（`distributed.ex:30-36`）。分散転換の段階的導入として妥当。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

**network プラス小計: +20**

---

## engine — apps/server

- **起動シーケンスの fail-fast** `+2`
  > Supervisor 起動後に `:main` ルームを起動し、失敗時は raise で即座に停止（`application.ex:32-40`）。半端な起動状態を許さない。
  > 対象ファイル: `engine/apps/server/lib/server/application.ex`

- **テスト環境の分離設計** `+2`
  > test では Endpoint `server: false`・UDP port 0（OS 割当）・Zenoh 無効・formula broadcast nil と、外部依存を全て遮断。ポート競合のない並列テストが可能。
  > 対象ファイル: `engine/config/test.exs`

**server プラス小計: +4**

---

## engine — rust/nif（Formula VM）

- **panic しないエラー境界設計** `+4`
  > 「ドメインエラーは NIF としては成功とし `Ok({:error, reason, detail})` を返す」方針をヘッダに明記（`formula_nif.rs:4-5`）し、decode/vm 全域が `Result` チェーン。`unwrap`/`expect` がホットパスに存在せず、不正バイトコードで BEAM を巻き込まない。NIF 境界設計としてプロダクション水準。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`

- **decode の全域バウンドチェック** `+3`
  > 全命令で `ensure_len`、レジスタ番号 `< 64` 検証、名前の UTF-8 検証（`decode.rs:36-171`）。未知 opcode・途中終端・範囲外レジスタがすべて型付きエラーになる。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`

- **saturating 算術によるオーバーフロー防御** `+2`
  > I32 の加減乗が `saturating_add/sub/mul` でパニックフリー（`vm.rs:123-149`）。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

- **Elixir 統合テストによる失敗モード網羅** `+2`
  > invalid_opcode・未初期化レジスタ・register_out_of_range・division_by_zero・store_not_found を Elixir 側テストで検証（10 テスト）。
  > 対象ファイル: `engine/apps/core/test/core/formula_test.exs`

**rust/nif プラス小計: +11**

---

## engine — rust/client

### アーキテクチャ・契約

- **クレート分離とセキュリティ境界** `+4`
  > render/window/network/audio/auth_client/system_ui の責務分離が明確。特に「システム UI（資格情報）はクライアント所有で Zenoh に一切流さない」（`system_ui/src/lib.rs:5-10`）というセキュリティ境界の明文化と実装の一致は高評価。
  > 対象ファイル: `engine/rust/client/system_ui/src/lib.rs`

- **golden E2E protobuf 契約テスト** `+4`
  > Elixir が生成した golden バイナリを Rust 側でデコードして意味一致を検証（`network/tests/render_frame_e2e_contract.rs`）。言語間契約の自動検証は個人プロジェクトで滅多に見ない水準。`render_frame_proto` を wgpu 非依存の薄層に分離し、責務の SSoT をテストコメントで指示している点も良い。
  > 対象ファイル: `engine/rust/client/network/tests/render_frame_e2e_contract.rs`

- **auth_client の資格情報管理** `+4`
  > refresh token は OS ネイティブ資格情報ストア（Windows Credential Manager / Keychain / Secret Service）にのみ保存、access token はメモリのみ（`token_store.rs:1-17`）。HTTPS 強制（localhost 以外の http 拒否・リダイレクト無効、`api.rs:36-50`）、GUI スレッドをブロックしないバックグラウンド保存 API まで整備。
  > 対象ファイル: `engine/rust/client/auth_client/src/token_store.rs`, `engine/rust/client/auth_client/src/api.rs`

### 描画・オーディオ

- **3D パイプラインの GPU バッファ戦略** `+3`
  > 「GPU バッファは new() 時に最大容量で事前確保し、毎フレーム write_buffer で上書き。create_buffer は行わない」を明記・実装し、CPU スクラッチも clear() 再利用（`pipeline_3d/mod.rs:6-8`）。フレームアロケーション抑制の定石を押さえている。
  > 対象ファイル: `engine/rust/client/render/src/renderer/pipeline_3d/mod.rs`

- **2D インスタンシング + コンテンツ WGSL 注入** `+3`
  > 共有クワッド + `SpriteInstance`（bytemuck Pod）で 1 draw call 大量描画。`RendererInit` でコンテンツ側 WGSL を差し替え可能にし、シェーダーまでコンテンツ交換可能性を拡張（`renderer/mod.rs:338-346`）。
  > 対象ファイル: `engine/rust/client/render/src/renderer/mod.rs`

- **AssetLoader のパストラバーサル防御** `+3`
  > `assets/` プレフィックス強制・`..` 拒否・バックスラッシュ拒否を実装し、`etc/passwd` や `assets/../Cargo.toml` を拒否する統合テスト付き（`audio/tests/relative_path.rs`）。サーバ由来の相対パスを扱う境界として正しい設計。
  > 対象ファイル: `engine/rust/client/audio/src/asset/mod.rs`

- **ヘッドレスレンダラー** `+2`
  > サーフェスなしでオフスクリーン描画→PNG 出力でき、CI での描画回帰確認の下地がある。
  > 対象ファイル: `engine/rust/client/render/src/headless.rs`

- **フレームホールド + audio_cues 再送防止** `+2`
  > 新フレーム未着時は直前フレームを再利用しつつ `audio_cues` をクリアして SE 二重再生を防ぐ（`network_render_bridge.rs:215-221`）。ネットワークジッター対策の実践的なディテール。
  > 対象ファイル: `engine/rust/client/network/src/network_render_bridge.rs`

- **オーディオのグレースフルフォールバック** `+2`
  > デバイス不在時も警告のみでコマンドを黙って破棄し、ゲーム本体を止めない（`audio.rs:132-136`）。mpsc コマンドスレッドで描画ループと分離。
  > 対象ファイル: `engine/rust/client/audio/src/audio.rs`

- **system_ui の状態機械テスト** `+2`
  > egui から分離した `Screen` 状態機械 + バリデーションに 16 ユニットテスト。auth のサーバ側バリデーション規則とクライアント側を同期させている。
  > 対象ファイル: `engine/rust/client/system_ui/src/state.rs`, `engine/rust/client/system_ui/src/validation.rs`

- **unsafe ゼロ** `+2`
  > クライアント全クレートで `unsafe` ブロック 0 件。GPU バッファは bytemuck の安全 API 経由。
  > 対象ファイル: `engine/rust/client/`（全体）

**rust/client プラス小計: +31**

---

## 横断評価層

### 開発者体験（DX）

- **mix alchemy.ci によるローカル CI 単一エントリ** `+4`
  > Rust fmt/clippy(-D warnings)/test + Elixir deps/format/credo --strict/test --warnings-as-errors を 1 コマンドに集約し、filter（rust/elixir/check）付き。GitHub Actions と同等性を保つ設計意図がコメントに明記されている。**本評価時に main ブランチで実行し ALL PASSED を確認**。
  > 対象ファイル: `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **proto-verify CI ジョブ（生成物ドリフト検出）** `+3`
  > CI 上で `mix alchemy.gen.proto` を再実行し `git diff --exit-code` で生成コードの手動改変・陳腐化を検出（`.github/workflows/ci.yml:56-87`）。契約の SSoT を守る仕組みとして優れる。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

### プロジェクト全体設計

- **moduledoc の文書化品質と誠実さ** `+3`
  > ほぼ全モジュールに設計意図・制約・歴史的経緯（「on_nif_sync は歴史的名称」「NIF 経路は撤去済み」等）を記述。実装と乖離した美化がなく、限界を認める記述（当たり判定近似、find_room_node のキャッシュ余地）が随所にある。ソースだけで設計判断が追える。
  > 対象ファイル: `engine/apps/`（全体）

- **エラー契約の一貫性** `+3`
  > Elixir 側 `{:ok, _} / {:error, reason}`・Formula の 3 要素タプル・Rust 側 `Result` が層をまたいで一貫。UDP/Zenoh の不正入力も型付きエラーに正規化され、握りつぶしがない。
  > 対象ファイル: 全域

- **テストの意図的設計** `+3`
  > OTP 隔離（kill 注入）、UDP 不正パケット耐性、golden 契約、async 可否の理由コメント付き使い分けなど、「何を守るためのテストか」が明確。数は少ないが設計品質は高い。
  > 対象ファイル: `engine/apps/network/test/`, `engine/rust/client/*/tests/`

- **構造化ログプレフィックス** `+2`
  > `[Network]` `[ROOM]` `[STRESS]` `[input:ZenohBridge]` 等の一貫したプレフィックスで grep 可能なログ体系。初回 N フレームのみ・60 フレームに 1 回などログ流量の制御も実装。
  > 対象ファイル: `engine/apps/`（全体）

- **技術的負債の少なさ** `+2`
  > TODO はリポジトリ全体で 5 件（engine/apps 4 + rust 1）、FIXME/HACK 0 件。auth は 0 件。負債が追跡可能な規模に収まっている。
  > 対象ファイル: 全域

**横断プラス小計: +20**

---

## 総計

| 大分類 | プラス小計 |
|:---|:---:|
| auth | +52 |
| engine — apps/core | +19 |
| engine — apps/contents | +18 |
| engine — apps/network | +20 |
| engine — apps/server | +4 |
| engine — rust/nif | +11 |
| engine — rust/client | +31 |
| 横断評価層 | +20 |
| **プラス合計** | **+175** |
