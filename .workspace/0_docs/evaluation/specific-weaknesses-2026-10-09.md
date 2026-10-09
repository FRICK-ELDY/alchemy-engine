# マイナス点 統合一覧 — 2026-10-09

評価日: 2026-10-09
検証対象: スーパープロジェクト `dd0eff1`（`main`）。`world-server` はサブモジュール。
統合元:
- 第1評価者（Claude Opus 5.5）: `opus/opus-specific-weaknesses-2026-10-09.md`（70 項目 / **-131**）
- 第2評価者（GPT-5.6 Sol）: `gpt/gpt-specific-weaknesses-2026-10-09.md`（34 項目 / **-90**）

両評価者は互いの当日文書を参照せずに独立して採点した。本文書は両者の指摘を突き合わせ、**採用点**を決めたものである。出典は **両者**／**Opus**／**GPT** で示す。まとめ作成者がコードを再読した項目は、その旨を書く。

採用は **69 項目 / -135**。同一の根は 1 行に統合した。細かい -1 を全部足すと Opus の -131 を超えるが、重複（認証既定と RoomToken の抱き合わせ、起動木とシーン共有、物理の不在を「VM 縮小の失敗」と二重に数えること）は落としている。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

---

## プロジェクト全体

### ビジョンと実装の一致

- **「IEEE 754 binary64 の 3D 座標系」を掲げ、ワイヤと描画は binary32** `-4` — **両者**（Opus -4 / GPT -4）
  > `vision.md` の一行要約と保証表が binary64 をエンジンの約束にしている。DrawCommand とクライアント契約は f32 である。説明責任の欠如であり、実装の優劣とは別問題である。
  > **採用判断**: 両者同点。**-4**。直すなら文言を実装に合わせるか、浮動原点の設計に着手するかを決める。中間の「だいたい 64bit」は置かない。
  > 対象ファイル: `.workspace/0_docs/vision.md`, `client/` の描画契約, protocol の `draw_commands`

- **ビジョンが「物理の基盤」を保証しているが、物理実装はない** `-3` — **両者**（Opus -2 / GPT -4）
  > NIF から物理・SoA・SIMD を撤去したこと自体はプラス側で採点する。残る欠陥は、保証文書が撤去後の器を説明していないことである。
  > **採用判断**: GPT の -4 は「物理エンジンとして採点できる実装がゼロ」であり、その読みは正しい。ただし不在は意図的縮小なので「存在しないに等しいエンジン」とはしない。文書が保証したままなのが欠陥であり、Opus -2 と GPT -4 の間の **-3** を採用する。
  > 対象ファイル: `.workspace/0_docs/vision.md`, `world-server/rust/nif`

- **Hub とリアルタイム編集が製品経路になっていない** `-2` — **GPT**（-3。Opus は save/load スタブとして別計上）
  > 編集・永続化はログを出すだけである。ビジョンの「作りながら遊ぶ」は経路として閉じていない。
  > **採用判断**: save/load 未配線（後述 -3）と根が近いため、Hub 全体の欠如は **-2** に抑える。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

### リポジトリ分割後の検証

- **4 リポジトリを横断する検証がない** `-3` — **Opus**（-3。GPT は保証文書の不一致として隣接指摘）
  > `PROTOCOL_PIN` の一致、golden の再生成と照合、認証付き入室の smoke を担う場所がスーパープロジェクトにない。子リポジトリの CI は緑でも、繋ぎ目は検出できない。
  > **採用判断**: **-3**。分割そのものはプラス側。
  > 対象ファイル: スーパープロジェクト（`.github` なし）, 各リポジトリの `PROTOCOL_PIN`

- **連合は read-only カタログ止まり** `-2` — **Opus**（-2）
  > S2S discovery まではある。配置と訪問でスライスを共有する連合には届いていない。
  > 対象ファイル: `world-server/apps/network`

- **前回改善計画の第 1 波が手つかず** `-2` — **Opus**（-2）
  > 2026-08-25 の第 1 波 6 件（クライアントテストの CI、prod 認証の fail-secure、Zenoh 再接続、保証文書、依存監査、Tetris の dt）は、現行ソースで未着手だった。
  > **採用判断**: プロセスの停止として **-2**。各技術項目は個別に再計上済みなので、ここで二重に重くしない。
  > 対象ファイル: `.workspace/0_reference/improvement-plan.md`

---

## world-server

### apps/contents

- **シーンスタックが全ルームで共有されている** `-4` — **両者**（Opus -4 / GPT -4）
  > 起動木が `Contents.Scenes.Stack` を 1 つだけ持ち、各コンテンツの `flow_runner/1` が `room_id` を捨てて同じ pid を返す。tick はルーム単位でも、シーン状態はグローバルである。
  > **採用判断**: 両者同点。器（`room_id` 付き登録、`scene_stack_spec/1`）はある。欠けているのは配線である。**-4**。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`, `world-server/apps/contents`

- **任意のクライアントが `"__quit__"` でノードを停止できる** `-4` — **Opus**（-4）
  > まとめ作成者が再読した。`Device.Keyboard` は `"__quit__"` を既定ハンドラに入れ、`:quit_requested` をイベントプロセスへ送る。`Events.Game` はコンテンツの `on_quit_requested/0` を呼び、`SampleOsc` / `CanvasTest` / `FormulaTest` はそこで `System.stop(0)` する。既定コンテンツの Quit ボタンも同じアクションを送る。キーボード側のコメントは「Keyboard は `System.stop` しない」と書いてあるが、停止は 1 段先で起きる。
  > **採用判断**: GPT は未検出。コードで確認できたため **-4** を採用する。今回の最優先修正である。
  > 対象ファイル: `world-server/apps/contents/lib/components/category/device/keyboard.ex`, `world-server/apps/contents/lib/events/game.ex`, `world-server/apps/contents/lib/contents/sample_osc.ex`

- **`Events.Game` に未知メッセージの受け皿がない** `-3` — **Opus**（-3）
  > `handle_info({:ui_action, action}, _)` は `action` が binary のときだけ受ける。非 binary は句に落ちず、GenServer が終了する。`"__quit__"` と組み合わさると、認証オフの既定では少数のメッセージでルームまたはノードを止められる。
  > **採用判断**: GPT は「失敗を黙って捨てる」に一部含む。クラッシュ面は独立なので **-3**。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **save / load がログのみ** `-3` — **両者**（Opus -3 / GPT -2）
  > `__save__` / `__load__` は Logger を出して状態を変えない。
  > **採用判断**: 永続化の不在は拡張を止める以上に、既存 UI が嘘になる。**-3**。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **Tetris が権威 tick を無視して 60Hz 固定** `-2` — **両者**（Opus -2 / GPT -2）
  > 対象ファイル: `world-server/apps/contents/lib/contents/tetris/playing.ex`

- **未実装スタブと未登録コンポーネント** `-2` — **Opus**（-2）
  > 対象ファイル: `world-server/apps/contents`

- **`contents` が `network` にコンパイル時依存する** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/contents`

- **`Device.Helpers` の 1 引数版が `:main` 固定** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/contents`

- **`ContentBehaviour` に実装者ゼロの武器・ボス・EXP コールバック** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/contents/lib/behaviour/content.ex`

- **既定コンテンツ・カタログ・コメントの不一致** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/contents`

### apps/core

- **`NifBridge.Behaviour` が未配線で NIF をモックできない** `-2` — **Opus**（-2）
  > 対象ファイル: `world-server/apps/core`

- **`FormulaStore` の synced ETS の所有者が不定** `-2` — **両者**（Opus -2 / GPT -2）
  > プロセス再起動後に表の寿命がオーナーに紐づかない。
  > 対象ファイル: `world-server/apps/core`

### apps/network

- **`AUTH_REQUIRED` が prod でも既定 false** `-3` — **両者**（Opus -3。GPT は RoomToken と合わせて -4）
  > 検証器は完成している。既定が安全側でない。
  > **採用判断**: RoomToken の subject 欠如とは別欠陥なので分割する。既定オフは **-3**。GPT の抱き合わせ -4 は採用しない。
  > 対象ファイル: `world-server/config/config.exs`

- **`RoomToken` が JWT の `sub` に束縛されない** `-3` — **両者**（Opus -3。GPT の抱き合わせ -4 の一部）
  > トークンを持っていれば、そのユーザーである保証がない。
  > **採用判断**: **-3**。
  > 対象ファイル: `world-server/apps/network/lib/network/room_token.ex`

- **公式クライアントが RoomToken を付けず、認証を有効にすると入室できない** `-4` — **両者**（Opus -3 / GPT -4）
  > `client/app` は認証クライアントを組むが、`NetworkRenderBridge` は生の protobuf を送る。auth-server の完成度が、出荷経路では無効になる。
  > **採用判断**: 部品ではなく製品経路が閉じない。GPT の **-4** を採用する。
  > 対象ファイル: `client/network` の `NetworkRenderBridge`, `client/app`

- **サーバ側 `ZenohBridge` が切断から復帰しない** `-3` — **両者**（Opus -3 / GPT -3）
  > クライアントは再接続するのに、サーバ購読は戻らない。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`

- **UDP に信頼性・リプレイ防止・断片化の契約がない** `-3` — **両者**（Opus -3 / GPT は入口制限と合わせて -3）
  > 対象ファイル: `world-server/apps/network`

- **UDP にパケット長・セッション数・送信頻度の上限がない** `-2` — **Opus**（-2。GPT の UDP 項目に含まれる）
  > **採用判断**: 契約の欠如（-3）とは別の DoS 面なので **-2** を残す。
  > 対象ファイル: `world-server/apps/network`

- **ルーム所在が全ノード RPC スキャン** `-2` — **両者**（Opus -2 / GPT は平文 HTTP と合わせて -2）
  > 対象ファイル: `world-server/apps/network`

- **S2S クライアントが平文 HTTP を許容する** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/network`

- **Zenoh 封筒形式を推測で判別している** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/network`

- **`GET /health` が稼働中ルーム ID を返す** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/network`

### apps/server

- **`RoomSupervisor` 再起動後に `:main` が復元されない** `-2` — **Opus**（-2）
  > `"__quit__"` や未知メッセージで `:main` が落ちたあと、戻る経路がない。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

- **release 定義と smoke がない** `-2` — **両者**（Opus -2 / GPT は起動木と合わせて -3）
  > **採用判断**: グローバル起動木そのものはシーン共有（-4）の原因として既に計上した。配布単位の欠如は **-2**。
  > 対象ファイル: `world-server`

- **server アプリの専用テストがゼロ** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/server`

- **`Application.start` が `ASSETS_ID` を `put_env` する** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

### rust/nif

- **通常スケジューラ NIF に命令数・入力サイズの上限がない** `-3` — **両者**（Opus -3 / GPT -3）
  > ユーザー定義バイトコードを DirtyCpu なしで走らせる。スケジューラを占有しうる。
  > 対象ファイル: `world-server/rust/nif`

- **ABI / バージョン契約とエラー分類が弱い** `-2` — **GPT**（-2）
  > 対象ファイル: `world-server/rust/nif`

- **入力エラーの返し方が例外とタプルに割れる** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/rust/nif`

- **Rust テストが除算に偏っている** `-1` — **Opus**（-1）
  > 対象ファイル: `world-server/rust/nif`

---

## client

### shared / network / render / window / audio / app

- **補間の対応付けが安定 ID ではなく最近傍** `-3` — **両者**（Opus -2 / GPT -3）
  > エンティティが交差すると補間先が入れ替わる。件数に対して二次である。
  > **採用判断**: 視覚的な誤りを起こす設計欠陥として GPT の **-3**。
  > 対象ファイル: `client/shared`

- **クライアント予測が恒等関数** `-2` — **両者**（Opus -2 / GPT -2）
  > 対象ファイル: `client/shared`

- **WASM トランスポートが空実装** `-2` — **両者**（Opus -2 / GPT -2）
  > 対象ファイル: `client/network`

- **render の回帰テストがなく、容量がコンテンツ知識の固定値** `-2` — **両者**（Opus はテスト -2 とカリング -1 を分割。GPT は -3）
  > **採用判断**: テストと固定容量を **-2**、カリングは別項。GPT の -3 はカリングと足しすぎになるため採用しない。
  > 対象ファイル: `client/render`

- **フラスタム・距離カリングがない** `-1` — **Opus**（-1）
  > 対象ファイル: `client/render`

- **音声キュー・同時発音・空間音響に上限がない** `-2` — **両者**（Opus は同時再生 -1。GPT -2）
  > デバイス不在のフォールバックはプラス側。3D オーディオ基盤としては未達なので **-2**。
  > 対象ファイル: `client/audio`

- **OpenXR が出荷 app に配線されていない** `-3` — **Opus**（-4。GPT は認証・XR・ネットワーク未閉を -3 に束ねた）
  > `client/app` に xr の参照はない。雛形クレートはある。
  > **採用判断**: ビジョンの一行要約は VR 出荷ではない。未配線は重いが、価値命題の破壊とまではしない。認証入室（-4）と二重に数えないため **-3**。
  > 対象ファイル: `client/app/src/main.rs`

- **`RenderFrame` を毎フレーム clone する** `-1` — **Opus**（-1）
  > 対象ファイル: `client/shared`

- **network クレートが描画・オーディオに依存する** `-1` — **Opus**（-1）
  > 対象ファイル: `client/network`

- **セッションエラー判定が文字列の部分一致** `-1` — **Opus**（-1）
  > 対象ファイル: `client/network`

- **移動入力を描画フレームごとに無条件 publish する** `-1` — **Opus**（-1）
  > 対象ファイル: `client/network`

- **ウィンドウ初期化の失敗で panic する** `-1` — **GPT**（-1）
  > 対象ファイル: `client/window`

- **クライアントテストが CI で実行されない** `-3` — **両者**（Opus -3 / GPT -4）
  > `client/.github/workflows` に `cargo test` がない。`shared` の補間テストを含む回帰がゲートになっていない。Opus は 52 件、GPT は 61 件と数えた。ファイル単位では interp 18 件ほか、50 件規模であることは確認した。正確な件数の差は採点を変えない。
  > **採用判断**: テストは存在し、fmt / clippy は CI にある。実行されないことは **-3**。品質ゲートが「存在しないに等しい」という GPT の -4 は採らない。
  > 対象ファイル: `client/.github/workflows/ci.yml`

---

## auth-server

### lib/auth と lib/auth_web

- **メール未検証でも access / refresh を発行する** `-3` — **両者**（Opus -2 / GPT -3）
  > 検証フローと `FOR UPDATE` はある。発行の条件になっていない。
  > **採用判断**: 作った認可が効かないのは設計欠陥。**-3**。
  > 対象ファイル: `auth-server/lib/auth`

- **リフレッシュローテーションに競合がある** `-2` — **Opus**（-2）
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`, `auth-server/lib/auth/token/refresh_token.ex`

- **最低年齢ポリシーがない** `-1` — **両者**（Opus -1。GPT は GC と合わせて -1）
  > 対象ファイル: `auth-server/lib/auth`

- **`account_tokens` が GC されない** `-1` — **Opus**（-1）
  > `TokenCleanup` は別経路の期限切れ削除であり、この表の寿命とは一致しない、という Opus の指摘を採用する。
  > 対象ファイル: `auth-server/lib/auth`

- **レート制限が単一ノード ETS** `-1` — **Opus**（-1）
  > 対象ファイル: `auth-server/lib/auth_web`

- **`/health` が DB 疎通を見ない** `-1` — **両者**（Opus -1。GPT は CORS と合わせて -2）
  > 対象ファイル: `auth-server/lib/auth_web`

- **CORS の allowlist がない** `-1` — **Opus**（-1）
  > 対象ファイル: `auth-server/lib/auth_web`

- **API 専用サービスに LiveView socket と cookie セッションが残る** `-1` — **Opus**（-1）
  > 対象ファイル: `auth-server/lib/auth_web`

### 不採用

- **auth のテストが 2 ファイルまで縮小した** — **GPT** の指摘。**不採用**。
  > `use ExUnit.Case` だけを数えると rate limit と keys に見える。`Auth.DataCase` 経由の `accounts_test.exs` ほかが残っており、`test "` は 100 件規模で存在する。Opus の「107 件」をプラス側で採用する。

---

## 横断

### テスト・観測・エラー・保守・DX・セキュリティ

- **プロパティベーステスト・fuzz・ベンチマークがない** `-2` — **両者**（Opus -2 / GPT -2）
  > 対象ファイル: `world-server`, `client`, `auth-server`

- **telemetry が ConsoleReporter と局所ログに留まる** `-2` — **両者**（Opus -2 / GPT -3）
  > **採用判断**: 本番観測の不足は -2。1000 人規模のトレース欠如は、その規模をまだ保証していない現状では -3 にしない。
  > 対象ファイル: `world-server/apps/core`

- **保証文書が分割前の CI と physics を説明している** `-3` — **両者**（Opus -3 / GPT -3）
  > `.workspace/0_docs/warranty/ci.md` が現行の 4 ワークフローと一致しない。評価ルールの physics 節も現行ツリーとずれる。
  > 対象ファイル: `.workspace/0_docs/warranty/ci.md`, `.cursor/rules/evaluation.mdc`

- **分割の残骸（コミットされた CI 出力、不要な apt パッケージ）** `-1` — **Opus**（-1）
  > 対象ファイル: 各リポジトリの CI 定義

- **`mix alchemy.ci` が world-server だけを見る** `-2` — **両者**（Opus -2 / GPT -2）
  > ローカルの単一入口が、対象の半分を保証しない。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **起動手順が Windows の `.bat` 前提** `-1` — **Opus**（-1）
  > 対象ファイル: リポジトリ直下の起動スクリプト

- **依存の脆弱性監査が 4 リポジトリにない** `-2` — **両者**（Opus -2。GPT は OS 配布と合わせて -3）
  > 対象ファイル: 各リポジトリ（`dependabot.yml` なし）

- **CI が Linux 単一で、クライアントの配布形態がない** `-2` — **両者**（Opus -2。GPT の抱き合わせ -3 の残り）
  > auth-server だけ release がある。world-server と client は配布単位になっていない。
  > 対象ファイル: `.github/workflows`

- **重要失敗を黙って捨てる経路がある** `-2` — **GPT**（-2）
  > 未知 UI を無視する箇所と、復旧不能な初期化が混在し、retryable / fatal の分類がない。catch-all 欠如（クラッシュ）とは別なので残す。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`, `client/window`

- **撤去済み語彙・旧パス・無効な TODO 検査が現状理解を妨げる** `-2` — **両者**（Opus は複数の -1。GPT -2）
  > Component の moduledoc、Telemetry のゲーム固有名、NIF の旧パス、`native/` 表記。個別 -1 の合算はせず **-2** にまとめる。
  > 対象ファイル: `world-server/apps/core`, `world-server/rust/nif`, `.workspace/0_docs`

- **完結したゲームは 2 本で、残りは技術デモ** `-2` — **Opus**（-3）
  > **採用判断**: コンテンツ差し替えが証明されていることと矛盾させない。量の不足は **-2**。エンジンの価値命題そのものの破壊ではない。
  > 対象ファイル: `world-server/apps/contents`

- **視覚・音響アセットが極薄** `-2` — **Opus**（-2）
  > 対象ファイル: `client`, `world-server/apps/contents`

---

**小計: 0 / -135 = -135点**（69 項目）
