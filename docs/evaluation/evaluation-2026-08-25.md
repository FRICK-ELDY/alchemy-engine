# AlchemyEngine 総合評価レポート — 2026-08-25（まとめ）

評価日: 2026-08-25
検証対象コミット: engine `8f35a57`（PR #347 マージ後、作業ツリークリーン）
対象:
- `engine/` — Elixir umbrella 4 アプリ（core / contents / network / server）+ `rust/nif`（Formula VM）+ `rust/client` 10 クレート
- `auth/` — Phoenix + Ash 認証サービス
- `assets/` — Phoenix + Ash アセット・永続化サービス（**今回から評価対象**）

前回評価: Fable 5 / 2026-07-31（`docs/evaluation/fable/archive/2026-07-31/`）

## 評価体制

本評価から **第1評価者（Claude Opus 5）と第2評価者（GPT-5.6 Sol）が互いの当日文書を読まずに独立評価し、その後まとめを作成する**二重化を導入した。両者はそれぞれ対象コードを直接読み、`mix alchemy.ci` の実行結果を確認して採点している。

| 文書 | 出力先 |
|:---|:---|
| 第1評価者の 4 文書 | `docs/evaluation/opus/` |
| 第2評価者の 4 文書 | `docs/evaluation/gpt/` |
| 統合一覧（本まとめ） | `docs/evaluation/specific-{strengths,weaknesses,proposals}-2026-08-25.md` |
| 改善提案書 | `workspace/0_reference/improvement-plan.md` |

> **評価期間中に CI が修正された**: 両評価者とも初稿では「GitHub Actions が `ci.yml.ignore` で無効」「`mix alchemy.ci` が 4 ジョブ赤」を重い減点として計上していた（Opus 計 -9、GPT 計 -8）。評価中に PR #347（`988b9e1` → マージ `8f35a57`）が入り、`ci.yml` の復活と fmt / clippy / format / credo の全違反修正が行われた。両評価者が現 HEAD で `elixir -S mix alchemy.ci` を再実行し **`RESULT: ALL PASSED`**（exit 0、21 秒）を確認したため、該当項目を撤回・緩和して再集計している。

---

## 総合スコア

### まとめ（採用値）

| 大分類 | プラス | マイナス | 総合 |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ・運用） | +12 | -4 | **+8** |
| auth（認証サービス） | +48 | -8 | **+40** |
| assets（永続化サービス、新規対象） | +13 | -9 | **+4** |
| engine — apps/core | +23 | -6 | **+17** |
| engine — apps/contents | +25 | -15 | **+10** |
| engine — apps/network | +26 | -19 | **+7** |
| engine — apps/server | +4 | -3 | **+1** |
| engine — rust/nif | +12 | -6 | **+6** |
| engine — rust/client | +45 | -18 | **+27** |
| 横断評価層（品質保証・ドキュメント） | +29 | -10 | **+19** |
| 横断評価層（ゲームプレイ完成度） | +4 | -6 | **-2** |
| **合計** | **+241** | **-104** | **+137** |

項目数: プラス 62 / マイナス 41 / 提案 36。両評価者の項目を突き合わせ、同一の根に対する重複を統合したうえでの件数である（プラス側は複数項目を 1 行に合算しているため、Opus の 97 項目・GPT の項目群を包含する）。

### 評価者間の比較

| 評価 | プラス | マイナス | 総合 |
|:---|---:|---:|---:|
| Fable 5（2026-07-31、前回） | +185 | -96 | +89 |
| 第1評価者 Opus（2026-08-25） | +257 | -69 | **+188** |
| 第2評価者 GPT（2026-08-25） | +215 | -119 | **+96** |
| **まとめ（採用）** | **+241** | **-104** | **+137** |

**両評価者の総合スコアは 92 点開いた。** 内訳は次のとおりである。

1. **プラス側の粒度と分類（+42）** — Opus はプラス点を 97 項目に細分化し、`StressMonitor` の配置や `EventBus` の monitor といった小さな設計判断まで個別に拾った。GPT は領域単位にまとめた。加えて Opus は「アーキテクチャ上の意思決定」を独立分類として +12 計上し、GPT はこの層に加点を置いていない。まとめでは Opus の粒度を採用しつつ、GPT が独立分類にした「ゲームプレイ完成度」+12 のうち contents 側と重複する +8 を落として +241 とした。
2. **マイナス側の重み（-50）** — GPT は「出荷経路で成立していないもの」を厳しく採点し（未配線 = -4）、Opus は「器と契約が既にあり残るのが配線のみ」なら緩める傾向を示した。合計差 -50 のうち約 -30 はこの傾向差で説明できる。まとめは影響が実際に読める範囲で中間を採った。
3. **検出漏れ（双方に存在、計 10 件）** — GPT のみが検出したものが 5 件（`RoomToken` の subject 未束縛 -3、Tetris の 60Hz 固定 -2、`FormulaStore` の ETS 非所有 -2、assets の非アトミック性 -2、S2S の平文 HTTP 許容 -1）、Opus のみが検出したものが 5 件（封筒形式のヒューリスティック判別 -1、`/health` のルーム ID 公開 -1、UDP の flood 耐性欠如 -2、assets の書き込みクォータ欠如 -1、`Helpers` の `:main` 固定 -1）。**独立二重評価を導入した最大の成果はこの 10 件である。**

重要なのは、**単独評価ではどちらの評価者も自分の判断バイアスに気づけなかった**という点である。第1評価者が単独で評価していれば、`8f35a57` は「マルチルーム対応完了」という誤った記録として残っていた。

---

## 総評

前回評価から 3.5 週間で 21 本の PR（#326〜#347）が入り、**総合 +89 → +137 と大きく前進した**。前回マイナス 48 項目のうち 14 件が解消、9 件が緩和され、新規実装 21 項目が加点された。

改善の「質」が特に高い。多くが「指摘された症状を消す」のではなく「原因を潰して再発を機械的に禁止する」形で直っている。象徴的な例を 3 つ挙げる。第 1 に Formula VM の除算バグは、型分岐による修正・`as_i32()` が F32 を truncate するという原因のコメント化・6 テストによる全パス固定という三点セットで応えている。第 2 に「core がコンテンツ語彙を握っている」というレイヤ違反は、参照を削るだけでなく `refute Map.has_key?(summary, :kills_by_enemy)` というテストを置き、破ったら落ちる状態にした。第 3 にネットワーク層の認証は、UDP・Zenoh・WebSocket に個別対応するのではなく `Network.RoomAuth` という単一モジュールに収束させ、`AUTH_REQUIRED` 有効時に JWKS URL 未設定なら起動時 raise という fail-fast の連鎖まで通した。

新規実装も密度が高い。`SnapshotInterpolator`（+5）は適応遅延バッファ・バースト除外・スポーン／デスポーン処理を備え、定数ごとに「なぜこの値か」の根拠がコメントに書かれ、18 テストで固定されている。read-only S2S（+2）は連合の第一歩を SSRF 拒否と JWKS 再取得ごと 471 行のテストで固めた。`alchemy-assets`（新規、+13）はパスポリシーの多層防御と JWT クレームの網羅検査を最初から正しく作っている。「動くものを作る」を超えて「壊れ方を先に考えて作る」段階に入っている。

**評価期間中に起きた出来事そのものが、このプロジェクトの性格をよく表した。** 初稿時点で両評価者が最も重く見たのは品質保証の崩壊だった。`.github/workflows/` には `ci.yml.ignore` しかなく、`README.md:89` は「すべての push で GitHub Actions が自動実行されます」と書いていた。`mix alchemy.ci` は main で 4 ジョブ赤で、2 大新規実装（`SnapshotInterpolator` と OpenXR ループ）はどちらも fmt / clippy を通っていなかった。これを指摘した直後に PR #347 が入り、**ワークフローを戻すだけでなく赤いジョブを先に全部緑にしてから戻す**という正しい順序で修正された。credo 対応は閾値の緩和ではなく関数分割で行われている。逃げていない。

一方で、独立二重評価が明らかにした事実として、**「前回の指摘リストを起点に解消を確認する」という進め方には系統的なバイアスがある**。第1評価者は次の 3 件を「解消した」または「軽微」と誤判定し、第2評価者が正しく捉えた（まとめ作成者が対象コードを再確認して第2評価者の判断を採用した）。

| 誤判定した項目 | Opus | GPT | 採用 | 誤判定の原因 |
|:---|:---:|:---:|:---:|:---|
| 全ルームが単一 `Contents.Scenes.Stack` を共有 | 初稿で解消と誤判定 → -4 に自己修正 | -5 | **-4** | `flow_runner/1` のシグネチャが room_id 化されたのを「本体の解消」と読み違えた。実装は `Process.whereis(Contents.Scenes.Stack)` で引数を捨てている |
| Tetris だけ固定 60Hz 前提 | 未計上 | -2 | **-2** | dt ベース化を「全コンテンツで完了」と読んだ。`update/2` が `context` を捨てており権威 20Hz で 1/3 速度になる |
| Elixir 側 `ZenohBridge` に再接続がない | 初稿で未計上 → -3 に自己修正 | -4 | **-3** | Rust クライアント側の再接続実装（+4 で評価）をもって前回指摘を解消と判断し、サーバ側を見落とした |

とくに 1 件目は深刻で、**今回加点した「全ルームで tick が回るようになった」という改善が、状態共有と組み合わさって新しい不具合を生んでいる**。2 ルーム起動すると同じシーン状態が 1 tick に 2 回更新され、ゲームが 2 倍速で進む。マルチルームは「1000 人規模」「連合」を掲げるこのプロジェクトの中心機能である。

もう一つ、前回まで採点されていなかった **ゲームプレイ完成度** を両評価者が独立に新設した。Content 5 種のうち開始 → プレイ → 終了 → リトライの全経路が閉じているのは Tetris のみで（それも 1/3 速度）、`BulletHell3D` はタイトル画面なし・敵種 1 種・プレイヤーの攻撃手段なし・単一アリーナである。アセットは音声 6 ファイルと atlas 1 枚で、ゲーム別ディレクトリは空。「コンテンツ交換可能性の実証」という目的には 5 例で十分だが、外部の人に渡して 10 分もたない。

総括すると、**設計・実装の質は同規模の個人プロジェクトの水準を大きく超えており、指摘に応える速度と正確さも際立っている。残る課題は「作る力」の問題ではなく、(1) 出荷経路で実際に成立しているかの検証、(2) 遊びの物量、(3) 守る仕組みを維持する制度、の 3 点に集約される。** とくに (1) は今回の 3 件の誤判定が示すとおり、「実装本体がある」ことと「経路として成立している」ことの区別を機械的に検出する手段（マルチルーム状態分離テスト、ゲームプレイ E2E、クライアントテストの CI 実行）が不足している。

---

## 最も評価できる点

両評価者が独立に +4 以上を付けた実装。これがプロジェクトの中核的な強みである。

| 実装 | 採用点 | 場所 |
|:---|:---:|:---|
| `SnapshotInterpolator`（適応遅延補間の実配線、18 テスト） | +5 | `rust/client/shared/src/interp.rs` |
| auth の暗号・トークン設計（RS256 マルチ鍵 JWKS + refresh family 再利用検知） | +5 | `auth/lib/auth/token/keys.ex`, `auth/lib/auth/accounts.ex` |
| 列挙安全な応答・ClientIp の trusted proxies・Authenticate プラグ | +5（3 項目合算） | `auth/lib/auth_web/` |
| テスト 107 件 + CI 品質ゲート + precommit | +5（2 項目合算） | `auth/test/`, `auth/.github/workflows/ci.yml` |
| 本番 release + 非 root Dockerfile + prod fail-fast + TokenCleanup | +8（4 項目合算） | `auth/Dockerfile`, `auth/lib/auth/token_cleanup.ex` |
| FormulaGraph コンパイラ + バイトコード契約 | +8（2 項目合算） | `apps/core/lib/core/formula/` |
| コンテンツ差し替えアーキテクチャ（5 実装で実証）+ ContentBehaviour | +6（2 項目合算） | `apps/contents/lib/behaviour/content.ex` |
| OTP ルーム隔離の実証テスト + protobuf 契約テスト | +6（2 項目合算） | `apps/network/test/` |
| `proto-verify` CI ジョブ + バージョンピン + 複合アクション | +6（3 項目合算） | `.github/workflows/ci.yml` |
| 3D バッファ戦略 + 2D インスタンシング + WGSL 注入 | +6（2 項目合算） | `rust/client/render/` |
| `AssetLoader` のパストラバーサル防御 + オーディオのフォールバック | +6（2 項目合算） | `rust/client/render/`, `rust/client/audio/` |
| ヘッドレスレンダラー + フレームホールド + `unsafe` 最小化 | +6（3 項目合算） | `rust/client/render/headless.rs` |
| Argon2id / 多軸レート制限 / アカウントライフサイクル | +4 ×3 | `auth/lib/auth/` |
| バックプレッシャー設計（メールボックス深度 + 副作用の切り分け） | +4 | `apps/contents/lib/events/game.ex` |
| 3 トランスポートの統一メッセージ収束 | +4 | `apps/network/lib/network/` |
| 認証・UDP 防御の vertical slice | +4 | `apps/network/lib/network/auth_verifier.ex` |
| golden E2E protobuf 契約テスト | +4 | `rust/client/network/tests/` |
| `auth_client` の資格情報管理（OS ネイティブストア） | +4 | `rust/client/auth_client/` |
| Zenoh publisher キャッシュ + 指数バックオフ再接続 | +4 | `rust/client/network/src/platform/desktop.rs` |
| クレート分離とセキュリティ境界（10 クレート） | +4 | `rust/Cargo.toml` |
| `mix alchemy.ci` によるローカル CI 単一エントリ | +4 | `apps/core/lib/mix/tasks/alchemy.ci.ex` |
| panic しないエラー境界設計（2 層） | +4 | `rust/nif/src/nif/formula_nif.rs` |
| `assets` の所有境界の強制 / 単一コミットで運用形態まで完備 | +4 ×2 | `assets/lib/assets/path_policy.ex` |

これに加えて、Opus が単独で高く評価した **NIF をゲームロジックから撤退させた判断**（+4）は、`ResourceArc` 使用ゼロ・`unsafe` 2 箇所という現在の健全さの直接の原因になっており、記録に残す価値がある。

## 最も深刻な弱点

| 項目 | 採用点 | 場所 |
|:---|:---:|:---|
| 全ルームが単一 `Contents.Scenes.Stack` / `EventBus` / `Stats` を共有 | **-4** | `contents/*.ex` の `flow_runner/1`, `server/application.ex` |
| OpenXR が出荷 app へ未配線・`XR_MND_headless` 限定 | **-4** | `rust/client/xr/`, `rust/client/app/src/main.rs` |
| Elixir 側 `ZenohBridge` に再接続がない（サーバ側だけ復旧しない） | **-3** | `network/zenoh_bridge.ex` |
| `AUTH_REQUIRED` が prod でも既定 false | **-3** | `config/config.exs`, `network/room_auth.ex` |
| engine → assets の save / load が未配線 | **-3** | `events/game.ex`, `core/formula_store.ex` |
| クライアント Rust テスト 52 件が CI で 1 件も実行されない | **-3** | `alchemy.ci.ex:99-106`, `ci.yml:50-51` |
| `RoomToken` が JWT subject に束縛されていない | **-3** | `network/room_token.ex` |
| 通常スケジューラ NIF に命令数・入力サイズ上限がない | **-3** | `rust/nif/src/formula/decode.rs` |
| UDP に信頼性・リプレイ・断片化の契約がない | **-3** | `network/udp/protocol.ex` |
| 保証ドキュメントと評価ルールが旧構成のまま | **-3** | `docs/warranty/ci.md`, `.cursor/rules/evaluation.mdc` |
| contents のテスト密度が低く状態分離の検証がない | **-3** | `apps/contents/test/` |
| 未実装コンポーネント・descriptor 実行系のスタブ残存 | **-3** | `apps/contents/lib/` |
| 実ゲームは 2 本、残り 3 本は技術デモ | **-3** | `apps/contents/lib/contents/` |

**-5 は 1 件もなく、-4 は 2 件に留まった**（前回は -4 が 4 件）。「壊れている」ではなく「まだ繋がっていない」種類の欠陥が中心という点が、今回のマイナス側の性格である。

---

## 前回指摘（Fable 2026-07-31）の到達状況

前回マイナス 48 項目すべてについて、両評価者が独立に対象ファイルを読み直して検証した。

### 解消（14 件）

`:main` 以外のルームでループが駆動しない（-4、ただし状態共有という別の欠陥が露出）／ Formula `binary_div` の float 除算バグ（-3）／ rust/nif の Rust 単体テストがゼロ（-3、6 件に）／ UDP の zlib 展開が無制限（-3）／ engine の SECRET_KEY_BASE に fail-fast なし（-3）／ Zenoh publisher を put ごとに宣言（-3）／ Formula `i32::MIN / -1` のパニック（-2）／ UDP セッションの無期限成長（-2）／ Rust クライアントの Zenoh 再接続なし（-2）／ FrameCache が単一スナップショット・ゲーム固有スキーマ（-2）／ contents → network の直接呼び出し（-2）／ Core.Stats が旧ゲーム前提（-1）／ 死にコード・死に設定の残存（-1）／ 出荷 tick_hz とコメントの矛盾（-1）

### 緩和（9 件）

連合機能の実装ゼロ（-4 → -2、read-only S2S が着地）／ 補間・予測が未配線（-4 → -2、補間のみ完了）／ auth ↔ engine 認証の分断（-3 → 解消、既定オフ -3 に論点が移動）／ UDP JOIN が無認証（-3 → 検証経路は完成、既定オフ -3 に統合）／ Zenoh 経由の入力が無認証（-2 → 同上に統合）／ `flow_runner(:main)` のハードコード（-3 → -4 に**悪化**。シグネチャは room_id 化されたが本体が引数を無視）／ contents のテスト密度（-3 → -3 を維持、スタブ残存と合わせて再構成）／ engine の永続化層の不在（-2 → -3、`assets` 新設だが未接続）／ OpenXR が実質スタブ（-4 → -4 を維持。実装は 296 行に前進したが起動経路がない）

### 維持（16 件）

`NifBridge.Behaviour` 未配線 / 未実装コンポーネント / `find_room_node` 全ノード RPC / UDP 断片化・再送なし / server テスト 0 件 / リリース定義不在 / Formula 命令数上限・DirtyCpu / client Rust テストが CI 外 / render テスト 0 件 / WASM 未実装スタブ / RenderFrame 毎フレーム clone / カリング・SE 上限なし / プロパティ・fuzz・bench 不在 / 可観測性の乖離 / 依存脆弱性監査なし / CI 単一 OS・配布手段なし、および auth の 7 項目（`lib/` 変更ゼロのため全件存続）

### 新規計上（14 件）

全ルームが単一 SceneStack を共有（-4）／ Elixir ZenohBridge 再接続なし（-3）／ RoomToken が JWT subject に未束縛（-3）／ Tetris 固定 60Hz（-2）／ UDP の生パケットサイズ・セッション数・レート制限なし（-2）／ `FormulaStore` の ETS が呼び出し元所有（-2）／ `Assets.Objects` の非アトミック性（-2）／ `network` クレートの逆依存（-2）／ 補間の対応付けが最近傍（-2）／ `docs/warranty/ci.md` と `evaluation.mdc` の陳腐化（-2）／ ゲームプレイ完成度 3 項目（-6）／ CI 無効化の再発パターン（-1）／ 封筒形式のヒューリスティック判別（-1）／ `GET /health` のルーム ID 露出（-1）ほか

---

## 次の優先改善

詳細と手順は `workspace/0_reference/improvement-plan.md` に記載する。ここでは順序と理由のみを示す。

| # | 改善 | 採用点への効果 | 見積 |
|:---:|:---|:---|:---:|
| 1 | CI の Rust テストを `-p nif` → `--workspace` にする | -3 が消え、`SnapshotInterpolator` の 18 テストが初めて回帰検出に使われる | 10 分 |
| 2 | ルームごとの `SceneStack` / `EventBus` / `Stats` 分離 + 状態分離テスト | -4 が消え、contents のテスト密度 -3 の一部も埋まる。マルチルームという中心機能が初めて成立する | 1 日 |
| 3 | Tetris を `context.dt` ベースに書き換える | -2 が消える。唯一の完結作品が設計意図どおりの速度で動く | 2 時間 |
| 4 | Elixir `ZenohBridge` に backoff 再接続 + 再購読 | -3 が消える。Rust 側の `reconnect_with_backoff` を移植するだけ | 半日 |
| 5 | `AUTH_REQUIRED` の prod 既定を true + RoomToken に `sub` を載せる | -3 と -3 が消える。実装は完成済みで、既定の反転とペイロード 1 フィールドの追加 | 半日 |
| 6 | engine ↔ assets の往復を 1 経路通す（Tetris のハイスコア） | -3 が消え、`assets` が初めて価値を出す。以降のワールド・アバターは同型の反復 | 1 日 |
| 7 | `docs/warranty/ci.md` / `evaluation.mdc` / README を実態に合わせる | -3 が消える。今回の評価で実際に齟齬を生じた | 1 時間 |
| 8 | CI 無効化の再発防止（branch protection の required checks + `hex.audit`） | -2 と -1 が消える。今回自力で緑に戻せた能力を制度で固定する | 1 時間 |
| 9 | Formula NIF の命令数上限 + `DirtyCpu` 指定 | -3 が消える。ユーザー製バイトコードを実行する前提での必須の防御 | 半日 |
| 10 | UDP のパケットサイズ上限・セッション数上限・`seq` 単調性チェック | -3 と -2 が消える。既存の sessions マップに足すだけ | 半日 |
| 11 | OpenXR を app に配線し `XR_MND_headless` 非対応時のフォールバックを持つ | -4 が消える。296 行の実装が初めて起動経路を持つ | 数日 |
| 12 | 既定コンテンツを Tetris にし、BulletHell3D に攻撃手段と敵種を追加 | ゲームプレイ完成度 -3 への最短の応答。設計上の障害はない | 数日 |

**#1〜#7 は合計 3 日程度で、採用マイナス 24 点分（-104 → -80）が消える。** いずれも新機能の追加ではなく既存実装の局所修正・配線・設定反転である。とくに #1 は 1 行の変更で、これを入れないままだと PR #347 で得た「CI が緑」という状態の意味が実際より広く読まれてしまう。

---

## 検証記録

評価ルール（`.cursor/rules/evaluation.mdc`）の「過去の評価文書を参照するだけで判断しない。必ず当該コードを直接読み、現状を検証してから採点する」に従い、両評価者が以下を実施した。

- **`elixir -S mix alchemy.ci` を 2 回実行** — `9da2712` で 132 秒 / exit 1 / `RESULT: FAILED — ["cargo fmt", "cargo clippy", "mix format --check-formatted", "mix credo --strict"]`。PR #347 マージ後の `8f35a57` で 21 秒 / exit 0 / `RESULT: ALL PASSED`（全 6 ステップ PASS）。
- **`.github/workflows/` の実体と履歴を確認** — 現在は `ci.yml`（5 ジョブ: rust-check / rust-test / proto-verify / elixir-check / elixir-test、`push: branches: ["**"]` + `pull_request`）。`git log --follow` でリネームの反復を確認。
- **PR #347（`988b9e1`）の差分を精査** — 13 ファイル、127 行追加 / 110 行削除。credo 対応が `.credo.exs` の閾値緩和ではなく関数分割であることを確認。
- **前回マイナス 48 項目すべてについて対象ファイルを再読** — 解消 14 / 緩和 9 / 維持 16、加えて auth 7 項目の存続確認。
- **評価者間で判断が分かれた 14 項目について、まとめ作成者が対象コードを再確認** — `flow_runner/1`（5 コンテンツすべて）、`server/application.ex` の children、`tetris/playing.ex` の `update/2` と `@tick_sec`、`zenoh_bridge.ex` の `init/1` と `handle_cast`、`formula_store.ex` の `init/0`、`assets/lib/assets/objects.ex` の `put/4` と `delete/2` を実際に開いて採用点を決定した。
- **リポジトリルートの `assets/`（alchemy-assets）を新規に評価** — lib 22 ファイル / テスト 3 ファイル・12 ケース。
- **`.credo.exs` と `docs/warranty/ci.md` の設定値を突き合わせ** — 4 点の不一致を確認（現 HEAD でも未修正）。
- **`engine/assets/` の実体を確認** — audio 6 ファイル + `sprites/atlas.png`、`vampire_survivor/` と `mini_shooter/` は `.gitkeep` のみ。
