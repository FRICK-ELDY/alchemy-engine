# プラス点 統合一覧 — 2026-10-09

評価日: 2026-10-09
検証対象: スーパープロジェクト `dd0eff1`（`main`）
統合元:
- 第1評価者（Claude Opus 5.5）: `opus/opus-specific-strengths-2026-10-09.md`（94 項目 / **+240**）
- 第2評価者（GPT-5.6 Sol）: `gpt/gpt-specific-strengths-2026-10-09.md`（36 項目 / **+116**）

採用は **99 項目 / +260**。Opus の細分を残し、同じ事実の二重計上（コンテンツ境界と `ContentBehaviour` の契約、リポジトリ分割と protocol SSoT）は 1 行に寄せた。GPT がより高く付けた項目は、その理由が「出荷経路で本当に効いているか」まで届いているときに採用した。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSSと比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## プロジェクト全体

### 定義と実行

- **Elixir が権威、クライアントが描画、という二層が実装で守られている** `+4` — **両者**（Opus +3 / GPT +4）
  > ゲームルールと描画定義は contents に残り、Rust は受け取ったフレームを描く。レイヤー境界の原則が、コメントではなく依存の向きになっている。
  > **採用判断**: GPT の +4。例外（contents の network 依存、旧語彙）はマイナス側で別計上する。
  > 対象ファイル: `world-server/apps/contents`, `client/render`

- **NIF を Formula VM に絞り、物理・SoA・SIMD を撤去した** `+4` — **両者**（Opus +4 / GPT +3）
  > 障害面が小さい VM に縮んだ。ゲームバランス値を Rust に置かない、という原則と一致する。
  > **採用判断**: 判断の質は Opus の +4。保証文書が物理を約束したままなのはマイナス側（-3）であり、この加点を打ち消さない。
  > 対象ファイル: `world-server/rust/nif`

- **層間依存を MFA の config 注入で切っている** `+3` — **Opus**（+3）
  > Zenoh 配信を contents から外へ注入できる。
  > 対象ファイル: `world-server/apps/core`, `world-server/apps/contents`

- **スーパープロジェクトと protocol の SSoT 分離、sha 検証付き `PROTOCOL_PIN`** `+4` — **両者**（Opus は分割 +3 と認証切り出しを分離。GPT は分離 +4）
  > 4 リポジトリ（world-server / client / auth-server / protocol）とピン解決は、変更範囲を予測しやすくした。
  > **採用判断**: 分割の設計は +4。横断 CI が無いことはマイナス側。認証サービスの切り出しは次項で残す。
  > 対象ファイル: スーパープロジェクト, `protocol`

- **認証を JWT / JWKS 契約の別サービスにした** `+2` — **Opus**（+2）
  > world-server は `sub` を検証する側に回れる形になっている。公式クライアントがその経路を使わないことはマイナス側。
  > 対象ファイル: `auth-server`, `world-server/apps/network`

- **protocol リポジトリ単体のコンパイル CI** `+1` — **Opus**（+1）
  > 対象ファイル: `protocol/.github/workflows`

---

## world-server

### apps/core

- **`Core.FormulaGraph`（DAG からバイトコード、循環検出付き）** `+4` — **Opus**（+4。GPT は Store と合わせて +3）
  > 対象ファイル: `world-server/apps/core`

- **バイトコード契約が Elixir と Rust の両方で明文化されている** `+4` — **Opus**（+4）
  > グラフコンパイラとは別の、境界そのものの契約である。
  > 対象ファイル: `world-server/apps/core`, `world-server/rust/nif`

- **`FormulaStore` の local / synced スコープ** `+3` — **Opus**（+3）
  > 所有者不定はマイナス側。スコープの切り方自体は良い。
  > 対象ファイル: `world-server/apps/core`

- **`Core.Component` による合成** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/core`

- **`RoomSupervisor` と `RoomRegistry` によるプロセス分離** `+2` — **両者**（Opus +2 / GPT +3）
  > tick のプロセス分離は実在する。シーン状態が外にあるため +3 にはしない。
  > 対象ファイル: `world-server/apps/core`, `world-server/apps/server`

- **tick レートのホワイトリストと起動時 raise** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/core`

- **`FrameCache` の ETS をルームより先に起動する** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/core`

- **`StressMonitor`** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/core`

- **`EventBus` が購読者を monitor して自動解除する** `+1` — **Opus**（+1）
  > 対象ファイル: `world-server/apps/core`

### apps/contents

- **メールボックス深さによるバックプレッシャー** `+4` — **両者**（Opus +4 / GPT +4）
  > フレームドロップが telemetry に出る。権威 tick の設計として、同規模の自作サーバより明確に良い。
  > 対象ファイル: `world-server/apps/contents`

- **`context.dt` による tick 非依存** `+2` — **Opus**（+2）
  > Tetris が例外であることはマイナス側。
  > 対象ファイル: `world-server/apps/contents`

- **差し替え可能な複数コンテンツ** `+4` — **両者**（Opus +3 / GPT +4）
  > Content / Scene / Component の境界で、別ゲームが同じ器に載っている。個人プロジェクトでこの境界が実装まで落ちているのは強い。
  > 対象ファイル: `world-server/apps/contents`

- **`FrameEncoder` による RenderFrame の protobuf 化** `+3` — **Opus**（+3。GPT は汎用フレーム収束 +3）
  > 対象ファイル: `world-server/apps/contents`

- **シーンスタック API（push / pop / replace）** `+2` — **Opus**（+2）
  > API はある。全ルーム共有はマイナス側。
  > 対象ファイル: `world-server/apps/contents`

- **Nodes / Structs による定義の構造化** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/contents`

- **パラメータをコンテンツ側に集約** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/contents`

- **OSC 連携がテスト付き** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/contents/lib/contents/sample_osc`

- **VR 入力の防御的ガード** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **Zenoh 配信を contents の外へ注入** `+2` — **Opus**（+3 を MFA と分割してこちらは +2）
  > アーキテクチャの MFA 加点と二重にしない。
  > 対象ファイル: `world-server/apps/contents`

- **命名の一貫性** `+1` — **Opus**（+1）
  > 対象ファイル: `world-server/apps/contents`

### apps/network

- **複数トランスポートが同じルームメッセージに収束する** `+4` — **両者**（Opus +4 / GPT +4）
  > Local / Phoenix / UDP / Zenoh が別ゲームループを持たない。
  > 対象ファイル: `world-server/apps/network`

- **UDP バイナリプロトコルの設計** `+3` — **Opus**（+3）
  > 信頼性の欠如はマイナス側。フレーミング自体は意図が見える。
  > 対象ファイル: `world-server/apps/network`

- **zlib 展開の 64KB 上限** `+3` — **Opus**（+3）
  > 対象ファイル: `world-server/apps/network`

- **UDP セッションの期限切れ掃除** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/network`

- **`ZenohBridge` の DoS 対策** `+3` — **Opus**（+3）
  > 再接続の欠如はマイナス側。
  > 対象ファイル: `world-server/apps/network`

- **`AuthVerifier` の JWKS RS256 検証** `+4` — **両者**（Opus +3 / GPT +4）
  > claim の見方が厳密である。既定オフとは独立に、検証器の質を採る。
  > 対象ファイル: `world-server/apps/network`

- **WebSocket は `AUTH_REQUIRED` に関係なく RoomToken 必須** `+3` — **Opus**（+3）
  > 対象ファイル: `world-server/apps/network`

- **network の分離テスト** `+3` — **Opus**（+3。Opus は 102 件と記録）
  > 今回 `mix test` は走っていない。テストの配置と意図はソースで確認できる範囲で採用する。
  > 対象ファイル: `world-server/apps/network/test`

- **protobuf の往復契約テスト** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/network/test`

- **分散時のフォールバック** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/network`

- **S2S の discovery** `+2` — **両者**（Opus +2 / GPT +2）
  > 対象ファイル: `world-server/apps/network`

### apps/server

- **prod の設定欠落で起動を止める fail-fast** `+2` — **両者**（Opus +2 / GPT +2）
  > 必須 content と秘密の欠落は起動前に落ちる。認証既定オフとは別である。
  > 対象ファイル: `world-server/config`

- **薄いエントリポイント** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps/server`

### rust/nif

- **panic を term で返すエラー境界** `+4` — **両者**（Opus +4 / GPT は算術 panic テスト +2）
  > NIF が BEAM を巻き込まない、という境界はプロダクションの必須線を超えている。
  > 対象ファイル: `world-server/rust/nif`

- **decode の全境界検査** `+3` — **Opus**（+3）
  > 命令数上限が無いことはマイナス側。境界検査そのものは残す。
  > 対象ファイル: `world-server/rust/nif`

- **型昇格のテスト** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/rust/nif`

- **saturating / checked 演算** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/rust/nif`

- **Elixir 側からの結合テスト** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server`

---

## client

### shared

- **`SnapshotInterpolator`** `+5` — **両者**（Opus +5 / GPT +5）
  > ジッタに応じた補間遅延、バースト、ギャップ、順不同、音声の一回性。Opus は別ターゲットディレクトリで `cargo test -p shared` を実行し 18 件 pass を確認した。このクラスの個人プロジェクトでは、テスト付きの適応補間は突出している。
  > 対象ファイル: `client/shared/src/interp.rs`

- **描画契約型を render から分離** `+2` — **GPT**（+3 をクレート分割と分けて +2）
  > 対象ファイル: `client/shared`

### network

- **Zenoh の指数バックオフ再接続、generation、publisher キャッシュ、lock 外 I/O** `+4` — **両者**（Opus +4 / GPT +4）
  > サーバ側に再接続が無いことと対になる。クライアント側は製品品質に近い。
  > 対象ファイル: `client/network/src/platform/desktop.rs`

- **Elixir 生成 golden による E2E 契約テスト** `+3` — **Opus**（+3。GPT は最新フレームと合わせて +4）
  > Opus は `render_frame_e2e_contract` 1 件の pass を確認した。生成側が照合しない問題はマイナス側の横断 CI に置く。
  > 対象ファイル: `client/network/tests/render_frame_e2e_contract.rs`

- **最新フレーム優先の容量 1** `+3` — **GPT**（+4 の一部を +3）
  > 遅れを描かない、という判断はネットゲームの定石として正しい。
  > 対象ファイル: `client/network`

### render / window / audio / app

- **wgpu の 2D instancing、3D、egui、コンテンツ WGSL** `+4` — **両者**（Opus はバッファ再利用 +3 とシェーダ分離 +3。GPT は統合 +4）
  > 個人プロジェクトの描画としては十分に高い。render graph が無いことは提案側に置く。
  > 対象ファイル: `client/render`

- **GPU バッファの再利用** `+3` — **Opus**（+3）
  > 統合加点と別に、アロケーション方針として残す。
  > 対象ファイル: `client/render`

- **headless のオフスクリーン描画** `+3` — **両者**（Opus +2 / GPT +3）
  > CI から呼べる形がある。回帰画像が無いことはマイナス側の「render テスト」に置く。
  > 対象ファイル: `client/render`

- **Surface lost からの復帰** `+1` — **Opus**（+1）
  > 対象ファイル: `client/render`

- **入力所有権とメニュー状態の分離、winit 正規化** `+3` — **両者**（Opus +2 / GPT +3）
  > ESC、システムメニュー、フォーカス喪失、カーソル復帰が状態として分かれている。
  > 対象ファイル: `client/window`

- **オーディオの専用スレッドとデバイス不在フォールバック** `+3` — **両者**（Opus +3 / GPT +3）
  > 対象ファイル: `client/audio`

- **アセット読み込みのパストラバーサル検査** `+3` — **Opus**（+3）
  > 対象ファイル: `client/audio`

- **認証クライアントの失敗で起動を止めない** `+2` — **Opus**（+2）
  > 対象ファイル: `client/app`, `client/auth_client`

- **クレート分割** `+3` — **Opus**（+3）
  > 対象ファイル: `client`

- **トークンの OS キーリング保存** `+4` — **Opus**（+4）
  > 対象ファイル: `client/auth_client`

- **`system_ui` のテスト** `+2` — **Opus**（+2。16 件と記録）
  > CI 未実行はマイナス側。テストの質は残す。
  > 対象ファイル: `client/system_ui`

- **`unsafe` が xr クレートに閉じている** `+2` — **Opus**（+2）
  > 対象ファイル: `client`

- **OpenXR ループの雛形** `+1` — **Opus**（+1）
  > 出荷経路に無いことはマイナス側。雛形の存在は +1 に留める。
  > 対象ファイル: `client`

- **client CI の fmt / clippy / app ビルド** `+1` — **Opus**（+1。GPT は子 repo CI +3 を横断へ）
  > テスト未実行と相殺しない。lint のゲートとしては +1。
  > 対象ファイル: `client/.github/workflows/ci.yml`

---

## auth-server

### lib/auth

- **RS256 複数鍵 JWKS とローテーション** `+5` — **Opus**（+5。GPT は Argon2 と合わせて +4）
  > 鍵の世代を公開面と一緒に設計している。個人の認証サービスとして突出している。
  > 対象ファイル: `auth-server/lib/auth`

- **リフレッシュの family ローテーションと再利用検知** `+5` — **両者**（Opus +4 / GPT +5）
  > 盗用トークンの再利用で family を落とす。競合ウィンドウはマイナス側（-2）。検知の設計は +5。
  > 対象ファイル: `auth-server/lib/auth`

- **Argon2id によるパスワードハッシュ** `+4` — **Opus**（+4）
  > 対象ファイル: `auth-server/lib/auth`

- **`jti` 失効とアカウント状態の検査** `+3` — **Opus**（+3）
  > 対象ファイル: `auth-server/lib/auth`

- **トークンを SHA-256 ハッシュで保存** `+3` — **Opus**（+3）
  > 対象ファイル: `auth-server/lib/auth`

- **アカウントライフサイクルをトランザクションで閉じる** `+4` — **両者**（Opus +4 / GPT +4）
  > パスワード変更、リセット、無効化がトークン失効と一緒に動く。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **メール検証フローの `FOR UPDATE`** `+3` — **Opus**（+3）
  > 発行ゲートになっていないことはマイナス側。ロックの実装は残す。
  > 対象ファイル: `auth-server/lib/auth`

- **Ash リソースの宣言的バリデーション** `+3` — **Opus**（+3）
  > 対象ファイル: `auth-server/lib/auth`

- **利用規約の同意記録** `+3` — **Opus**（+3）
  > 対象ファイル: `auth-server/lib/auth`

- **期限切れデータの定期削除** `+2` — **Opus**（+2）
  > 対象ファイル: `auth-server/lib/auth`

- **release と Dockerfile** `+3` — **両者**（Opus +3 / GPT +2）
  > 4 サービスの中で、配布単位として閉じているのはここだけである。+3。
  > 対象ファイル: `auth-server`

- **runtime 設定の fail-fast** `+2` — **Opus**（+2）
  > 対象ファイル: `auth-server/config`

- **短い JWT TTL（15 分）** `+1` — **Opus**（+1）
  > 対象ファイル: `auth-server/lib/auth`

### lib/auth_web

- **12 バケットのレート制限** `+4` — **Opus**（+4。GPT は境界 +4 と多軸 +3）
  > IP、識別子、メール、family を分けている。単一ノード ETS はマイナス側。
  > 対象ファイル: `auth-server/lib/auth_web`

- **公開・認証・レート制限のパイプライン分離** `+3` — **GPT**（+4 をバケットと分けて +3）
  > 対象ファイル: `auth-server/lib/auth_web`

- **`Authenticate` の失敗情報の扱い** `+3` — **Opus**（+3）
  > 対象ファイル: `auth-server/lib/auth_web`

- **アカウント列挙を防ぐ応答** `+2` — **両者**（Opus +2 / GPT の列挙耐性に含む）
  > 対象ファイル: `auth-server/lib/auth_web`

- **`ClientIp` の信頼プロキシ** `+2` — **Opus**（+2）
  > 対象ファイル: `auth-server/lib/auth_web`

- **CI と `mix precommit`** `+2` — **Opus**（+2）
  > 対象ファイル: `auth-server`

- **テストがアカウントとトークンのライフサイクルを覆う** `+4` — **Opus**（+4。107 件と記録）
  > GPT は `use ExUnit.Case` のみ数えて 2 ファイルとした。`Auth.DataCase` 配下に登録・ログイン・トークンのテストが残っているため、縮小とは採用しない。実行通過は今回未確認なので、配置の厚みとして +4。
  > 対象ファイル: `auth-server/test`

- **world-server との契約文書** `+2` — **Opus**（+2）
  > 対象ファイル: `auth-server`, `.workspace/0_docs`

- **統一されたエラー JSON** `+1` — **Opus**（+1）
  > 対象ファイル: `auth-server/lib/auth_web`

---

## 横断

### テスト・DX・文書

- **層ごとにテストの責務を分けている** `+3` — **両者**（Opus +3 / GPT +3）
  > 時間、ワイヤ、セキュリティに焦点がある。ゲートになっていないことはマイナス側。
  > 対象ファイル: `world-server`, `client`, `auth-server`

- **`mix alchemy.ci`** `+3` — **Opus**（+3。GPT +2）
  > world-server の入口としては良い。対象外の子リポジトリはマイナス側。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **world-server CI の proto-verify** `+3` — **Opus**（+3）
  > 対象ファイル: `world-server/.github/workflows`

- **protoc / protobuf のバージョン固定** `+1` — **Opus**（+1）
  > 対象ファイル: `world-server/.github`

- **CI セットアップの composite action** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/.github`

- **moduledoc の充実** `+2` — **Opus**（+2）
  > 対象ファイル: `world-server/apps`

- **NIF と auth のエラー契約** `+2` — **Opus**（+2。GPT は graceful degradation +3 を別観点）
  > 対象ファイル: `world-server/rust/nif`, `auth-server`

- **境界ごとのフォールバック（音声デバイス、surface、JWKS 再取得、不正入力）** `+3` — **GPT**（+3）
  > 黙って捨てる経路はマイナス側。残るフォールバックは意図的である。
  > 対象ファイル: `client/audio`, `client/render`, `world-server/apps/network`

- **作業レーン（backlog / doing / done）** `+2` — **Opus**（+2）
  > 対象ファイル: `.workspace`

- **自己評価サイクルの仕組み** `+2` — **Opus**（+2）
  > 第 1 波が止まっていることはマイナス側。仕組みの存在は残す。
  > 対象ファイル: `.cursor/rules/evaluation.mdc`

- **構造化ログ（認証失敗、レート制限）** `+2` — **両者**（Opus +2 / GPT +2）
  > 対象ファイル: `auth-server`

- **技術的負債の文書追跡** `+1` — **Opus**（+1）
  > 対象ファイル: `.workspace`

- **子リポジトリごとの警告を落とす CI** `+2` — **GPT**（+3）
  > client がテストを走らせないため +3 にはしない。
  > 対象ファイル: `world-server/.github`, `client/.github`, `auth-server/.github`, `protocol/.github`

- **保証と非保証を文書化する姿勢** `+2` — **GPT**（+2）
  > 中身がコードとずれることはマイナス側。書く対象を決める姿勢は残す。
  > 対象ファイル: `.workspace/0_docs/vision.md`

---

**小計: +260 / 0 = +260点**（99 項目）
