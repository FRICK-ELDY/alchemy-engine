# AlchemyEngine — 改善計画

> このドキュメントは現在の弱点を整理し、各課題に対する具体的な改善方針を定義する。
> 最新の評価: [evaluation-2026-08-25.md](../../docs/evaluation/evaluation-2026-08-25.md)（まとめ）
> プラス点: [specific-strengths-2026-08-25.md](../../docs/evaluation/specific-strengths-2026-08-25.md) / マイナス点: [specific-weaknesses-2026-08-25.md](../../docs/evaluation/specific-weaknesses-2026-08-25.md) / 提案: [specific-proposals-2026-08-25.md](../../docs/evaluation/specific-proposals-2026-08-25.md)
> 評価者別の詳細: [opus/](../../docs/evaluation/opus/)（第1評価者）/ [gpt/](../../docs/evaluation/gpt/)（第2評価者）
> 過去のまとめ: [docs/evaluation/archive/](../../docs/evaluation/archive/) / Fable 系: [docs/evaluation/fable/archive/](../../docs/evaluation/fable/archive/)

---

## この計画の位置づけ

本計画は **2026-08-25 のまとめ評価で採用したマイナス点 56 項目・合計 -104** をすべて課題として引き受け、費用対効果順に並べたものである。提案（0 点）は本計画には含めない。新規の発展方向は [specific-proposals-2026-08-25.md](../../docs/evaluation/specific-proposals-2026-08-25.md) を参照する。

前版（2026-04-01 時点）は Fable 単独評価を前提に D-1〜D-7 の 7 課題を並べていた。今回の刷新で全面的に置き換えている。旧課題の帰結は末尾の「前版からの引き継ぎ」に整理した。

## スコアカード（2026-08-25 まとめ）

| 大分類 | マイナス採用 | 項目数 | 本計画での扱い |
|:---|:---:|:---:|:---|
| プロジェクト全体（アーキテクチャ） | -4 | 2 | P-5 / P-25 |
| auth（認証サービス） | -8 | 7 | P-19 |
| assets（永続化サービス） | -9 | 5 | P-9 / P-13 / P-20 |
| engine — apps/core | -6 | 4 | P-18 |
| engine — apps/contents | -15 | 7 | P-6 / P-7 / P-13 / P-17 |
| engine — apps/network | -19 | 9 | P-2 / P-3 / P-8 / P-15 / P-16 / P-25 |
| engine — apps/server | -3 | 2 | P-13 / P-23 |
| engine — rust/nif | -6 | 3 | P-11 / P-12 / P-13 |
| engine — rust/client | -18 | 9 | P-1 / P-10 / P-13 / P-21 |
| 横断（品質保証・ドキュメント） | -10 | 5 | P-4 / P-5 / P-14 / P-22 / P-23 |
| 横断（ゲームプレイ完成度） | -6 | 3 | P-13 / P-24 |
| **合計** | **-104** | **56** | P-1〜P-25 |

検証基準は現行どおり **`mix alchemy.ci` がエラーゼロで通過すること**（[docs/warranty/ci.md](../../docs/warranty/ci.md)）。2026-08-25 時点の `8f35a57` で `RESULT: ALL PASSED` を確認済みである。

## 優先度の考え方

1. **第 1 波（P-1〜P-6）** — 1 行〜半日で消え、以後の作業の安全網になるもの。合計 **-17**。
2. **第 2 波（P-7〜P-12）** — 「実装本体はあるが出荷経路で成立していない」ものを成立させる。合計 **-19**。
3. **第 3 波（P-13〜P-25）** — 面を広げる継続投資。合計 **-68**。

第 1 波と第 2 波を終えると採用マイナスは **-104 → -68** になる。いずれも新規機能ではなく、既存実装の配線・反転・局所修正で済む点が今回の特徴である。

### まとめレポートの優先順位との対応

[evaluation-2026-08-25.md](../../docs/evaluation/evaluation-2026-08-25.md) の「次の優先改善」#1〜#12 は、本計画では次の課題に対応する。

| まとめ # | 本計画 | まとめ # | 本計画 |
|:---:|:---|:---:|:---|
| 1 | P-1 | 7 | P-4 |
| 2 | P-7 | 8 | P-5 |
| 3 | P-6 | 9 | P-11 |
| 4 | P-3 | 10 | P-15 |
| 5 | P-2 + P-8 | 11 | P-10 |
| 6 | P-9 | 12 | P-24 |

---

## 第 1 波 — 即効（合計 -17）

### P-1: クライアント Rust テストを CI に載せる

**優先度**: 最高（費用対効果が全課題中で最大）

**問題**: `mix alchemy.ci` の Rust テストは `cargo test -p nif` のみで、GitHub Actions も同じ。クライアント側に実在する 52 件の `#[test]`（shared 18 / system_ui 16 / auth_client 8 / network 6 / audio 2 / render_frame_proto 2）が 1 件も回帰検出に使われていない。今期最大の成果である `SnapshotInterpolator` の 18 テストも同様である。

**方針**: `-p nif` を `--workspace` に変える。`app` / `render` など GPU・OS 依存クレートのビルドが CI で重い場合は `--workspace --exclude app` から始め、除外理由をコメントに残す。

**対象**: `apps/core/lib/mix/tasks/alchemy.ci.ex`（99-106 行）, `.github/workflows/ci.yml`（50-51 行）

**期待効果**: 「クライアント Rust テストが CI 対象外」**-3** が消える。以後 P-13 で書くテストが自動的に守られる状態になる。

---

### P-2: prod の認証を fail-secure に反転する

**優先度**: 最高

**問題**: `config :network, :auth_required, false` が既定で、`RoomAuth.required?/0` が false のときトークンを無視して常に `:ok` を返す。JWKS 取得 + RS256 検証と UDP / Zenoh の検証経路は完成しているのに、既定が安全側でないため運用者が 1 手忘れた瞬間に無認証で入室できる。

**方針**: `:prod` の既定を true に反転し、明示的な `AUTH_REQUIRED=false` のときだけ無認証を許す。`runtime.exs` に既にある fail-fast の作りを流用し、`auth_required` が true で JWKS URL 未設定なら起動時に `raise` する。dev / test の既定は据え置く。

**対象**: `config/config.exs`（57 行）, `config/runtime.exs`, `apps/network/lib/network/room_auth.ex`

**期待効果**: 「`AUTH_REQUIRED` が prod でも既定 false」**-3** が消える。

---

### P-3: Elixir 側 `ZenohBridge` に再接続を実装する

**優先度**: 高

**問題**: `init/1` で subscriber を 3 本宣言したあと死活監視が存在しない。`handle_info/2` に `:DOWN` 処理も再宣言もなく、未知メッセージは debug ログに落ちるだけである。Rust クライアント側には指数バックオフ再接続と再購読が入ったため、**zenohd 再起動時にクライアントだけが復帰してサーバは購読を失ったまま生き続ける**。片側だけ回復する非対称は、両方落ちるより発見が遅れる。

**方針**: Rust 側 `reconnect_with_backoff`（`rust/client/network/src/platform/desktop.rs:279-331`）と同型の実装を移植する。セッションを monitor し、`:DOWN` で 500ms → ×2 → 上限 8s のバックオフ再接続と subscriber 再宣言を行う。多重実行を防ぐゲートも同様に置く。再接続回数を telemetry に出す（P-22 の先取り）。

**対象**: `apps/network/lib/network/zenoh_bridge.ex`

**期待効果**: 「Elixir 側 `ZenohBridge` に再接続がない」**-3** が消える。

---

### P-4: 保証・評価ドキュメントを実態へ追従させる

**優先度**: 高（説明責任）

**問題**: 品質保証を説明する文書自体が最も陳腐化している。`docs/warranty/ci.md` は撤去済みクレートの `cargo test -p physics` と存在しない `cargo bench -p physics` ジョブを掲載し、`CyclomaticComplexity` を 15 と書くが `.credo.exs` は 10、`AliasUsage` は実際には無効化、実在する `proto-verify` ジョブは未記載である。README の「main のみ `cargo bench` のリグレッション検知」も事実でない。加えて `.cursor/rules/evaluation.mdc` の技術評価層が旧レイアウト（`native/physics` / `native/tools/launcher`）を前提にしており、現行の `rust/nif` + `rust/client/*` と対応しない。

**方針**: (1) `ci.md` の CI ジョブ表と credo 設定表を `.github/workflows/ci.yml` と `.credo.exs` の現物に合わせて書き直す。(2) README の bench 記述を削除する。(3) `evaluation.mdc` の技術評価層を現行クレート構成に更新する。(4) 再発防止として、`ci.yml` / `.credo.exs` の変更時に `ci.md` を同時更新する旨を `ci.md` 冒頭に明記する（自動生成は提案側に切り出す）。

**対象**: `docs/warranty/ci.md`, `README.md`, `.cursor/rules/evaluation.mdc`, `.credo.exs`（参照のみ）

**期待効果**: 「保証ドキュメントと評価ルールが旧構成のまま」**-3** が消える。今回の評価で実際に齟齬を生じた箇所である。

---

### P-5: CI 再無効化の歯止めと依存脆弱性監査

**優先度**: 高

**問題**: (1) 現 HEAD は `ci.yml` が有効で `mix alchemy.ci` も ALL PASSED だが、再発パターンが問題である。`ci ignore` ↔ 再有効化の往復が履歴に 4 回以上あり、今回の無効化期間は PR #326〜#345 の 20 本と重なった。required checks / branch protection は設定されていない（-2）。(2) `cargo audit` / `mix hex.audit` が CI・aliases とも未組込で、`dependabot.yml` はリポジトリ全体で 0 件。zenoh / wgpu / rustls / Ash と更新の速い依存を多数抱えている（-1）。

**方針**: (1) main への branch protection を有効にし、5 ジョブ（rust-check / rust-test / proto-verify / elixir-check / elixir-test）を required checks に登録する。ワークフローファイルのリネームで検査を外せてしまう構造なので、`.github/CODEOWNERS` で `.github/workflows/` を保護対象に加える。(2) `mix.exs` の alias に `hex.audit` を足し `ci.yml` に `cargo audit` ステップを追加、`.github/dependabot.yml` で cargo / hex / github-actions の週次更新を有効にする。どちらも CI 設定を触る作業なので同時に行うのが安い。

**対象**: `.github/workflows/ci.yml`, リポジトリ設定（branch protection）, `.github/CODEOWNERS`（新規）, `mix.exs`, `.github/dependabot.yml`（新規）

**期待効果**: 「CI 再無効化を防ぐ強制力がない」-2 と「依存の脆弱性監査がない」-1 の計 **-3** が消える。自力で緑に戻せた能力を制度として固定する。

---

### P-6: `Tetris` を dt ベースに書き換える

**優先度**: 高（費用対効果が大きい）

**問題**: `Tetris` だけが `@tick_sec 1.0 / 60.0` と `@base_drop_frames 45` というフレーム数ベースの落下タイマーを持ち、`update/2` が `context` を捨てている。権威 tick は既定 20Hz なので実速度が意図の 1/3 になる。「tick_hz を変えてもゲーム速度が変わらない」という設計上の主張に対する反例が、**唯一の完結した作品**の中に残っている状態である。

**方針**: 他 4 コンテンツと同じく `context.dt` を受けて落下タイマーを秒ベースに書き換える。前例があるため設計判断は不要で、`@base_drop_frames` を `@base_drop_seconds` に読み替え、レベルによる加速も秒で表現する。tick_hz を 10 / 20 / 30 に変えて落下速度が一定であることをテストで固定する。

**対象**: `apps/contents/lib/contents/tetris/playing.ex`

**期待効果**: 「`Tetris` だけが固定 60Hz 前提」**-2** が消える。体験に直接効く 2 時間の作業である。

---

## 第 2 波 — 中心機能を経路として成立させる（合計 -19）

### P-7: ルームごとにシーン状態を分離する

**優先度**: 最高（中心機能）

**問題**: `Server.Application` が `Contents.Scenes.Stack` を `room_id` なしで単一起動し、5 つの Content すべてが `def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)` と `room_id` を捨てて同じ pid を返す。tick 自体は全ルームで回るため「マルチルーム対応済み」に見えるが、2 ルームで同じコンテンツを動かせば HP・スコア・シーン遷移が相互に上書きされる。`Stack` は `room_id` 付き登録に対応済みで、`ContentBehaviour` には `scene_stack_spec/1` という optional callback まで用意されているのに、実装した Content が 1 つもない。**器はあり、欠けているのは配線とテストだけである。**

**方針**: (1) 各 Content に `scene_stack_spec/1` を実装させ、`flow_runner/1` が `room_id` から Registry 経由で当該ルームの `Stack` を引くようにする。(2) `Stack` をルーム supervision subtree（`RoomSupervisor` 配下）へ移す。(3) `EventBus` / `Stats` についても同じ観点で所有者を確認する。(4) 「2 ルームで同じコンテンツを起動し、片方のスコアが他方に影響しない」ことを検証するテストを追加する。

**対象**: `apps/contents/lib/contents/{bullet_hell_3d,tetris,canvas_test,formula_test,sample_osc}.ex`, `apps/contents/lib/scenes/stack.ex`, `apps/server/lib/server/application.ex`, `apps/core/lib/core/room_supervisor.ex`, `apps/contents/test/`

**期待効果**: 「シーンスタックが全ルームで共有されている」**-4** が消える。加えて P-13 の「状態分離の検証がない」部分（-3 のうち相当分）を先に埋める。マルチルームが初めて実機能になる。

---

### P-8: `RoomToken` を JWT subject に束縛する

**優先度**: 高（セキュリティ）

**問題**: `Network.RoomToken` のペイロードは `room_id` のみでユーザー識別子を含まない。`AUTH_REQUIRED=true` で `/api/room_token` が Bearer JWT を検証しても発行される RoomToken に `sub` が伝播しないため、(1) トークンを入手した第三者が誰としてでも入室でき、(2) サーバがセッションをユーザーに紐付けられない。認証層を作り込んだ後に残る、最も本質的な穴である。

**方針**: `Phoenix.Token.sign` のペイロードを `%{room_id: ..., sub: ...}` に拡張し、join 時に `sub` を session state に載せる。3 トランスポート（Channel / UDP / Zenoh）すべてが `Network.RoomAuth` に収束しているため変更点は 1 モジュールに閉じる。P-9 のユーザー別セーブは `sub` が前提になるので、この順序で行う。

**対象**: `apps/network/lib/network/room_token.ex`, `apps/network/lib/network/router.ex`, `apps/network/lib/network/room_auth.ex`

**期待効果**: 「`RoomToken` が JWT subject に束縛されていない」**-3** が消える。「認証したことがゲーム内の identity になる」状態が初めて成立する。

---

### P-9: engine ↔ assets の往復を 1 経路通す

**優先度**: 高（価値命題）

**問題**: `assets` サービスは Objects CRUD・所有権強制・JWKS 検証・Docker Compose・CI を備えて動作する状態だが、engine 側の `"__save__"` / `"__load__"` は「local persistence disabled; network TBD」のログを出すだけである。`FormulaStore` の synced スコープも ETS のみで再起動すれば消える。サービス追加から 18 日間、engine・client のどちらにも `assets` を呼ぶコードがない。

**方針**: Tetris のハイスコア 1 スロットだけを `schema_version` 付き JSON で往復させる。保存パスは定義済みの `users/{sub}/private/Save/{content_id}/save.{slot}` を使い、ユーザー JWT の代理送出は `assets/README.md` のパターン A に従う。この 1 経路で (1) engine → assets の HTTP クライアント、(2) JWT 代理送出、(3) セーブ／ロードの UI アクション の 3 つの型が同時に決まるため、以降のワールド・アバターは同型の反復になる。

**対象**: `apps/contents/lib/events/game.ex`（106-111 行）, `apps/network/`（HTTP クライアント新設）, `assets/lib/assets_web/controllers/object_controller.ex`（参照）

**期待効果**: 「engine → assets の save / load が未配線」**-3** が消える。`assets` が初めて価値を出す。

---

### P-10: OpenXR を出荷 app に配線する

**優先度**: 高（価値命題）

**問題**: `openxr_loop.rs` はセッション状態機械・action set・pose / ボタンの `XrInputEvent` 化まで書かれた実装になったが、(1) `app/src/main.rs` に `xr` クレートの参照がなく起動経路がない、(2) `xr/Cargo.toml` で `default = []`・`openxr` は optional のため既定ビルドに含まれない、(3) `XR_MND_headless` を必須とし未対応ランタイムでは即 `Err` で Monado 系に事実上限定される。結果として **VR は動かない**。

**方針**: 「動く経路が 1 本ある」状態を先に作る。(1) `app` に `xr` を feature 付きで依存させ、起動フラグまたは環境変数で XR ループに入る経路を通す。(2) `XR_MND_headless` 非対応ランタイムでは通常セッションへフォールバックし、それも不可なら明示的なエラーメッセージでデスクトップ経路に落ちる。(3) `XrInputEvent` をネットワークの入力エンコードに接続する。conformance スモークテストは提案側（`specific-proposals`）に置いた。

**対象**: `rust/client/app/src/main.rs`, `rust/client/xr/Cargo.toml`, `rust/client/xr/src/openxr_loop.rs`

**期待効果**: 「OpenXR が出荷 app へ未配線」**-4** が消える。

---

### P-11: Formula VM に実行上限と `DirtyCpu` を入れる

**優先度**: 高（順序が重要）

**問題**: `decode_bytecode` は `while pos < bytecode.len()` で EOF まで無制限に命令を積み、`run_formula_bytecode` は `#[rustler::nif]` のみで `schedule = "DirtyCpu"` を指定していない。**ユーザー作成コンテンツを実行する VM** としては、巨大バイトコード 1 本で BEAM の通常スケジューラを専有できる。

**方針**: (1) バイトコード長の上限と命令数上限を定数として置き、超過時は `DecodeError` で拒否する。(2) `schedule = "DirtyCpu"` を指定する。(3) 実行ステップ数の gas カウンタを VM に持たせる。**制御フロー命令（分岐・ループ）を追加する前に必ずこれを入れる**。ループが入った瞬間に「1 命令で無限ループ」が可能になる。

**対象**: `rust/nif/src/formula/decode.rs`, `rust/nif/src/formula/vm.rs`, `rust/nif/src/nif/formula_nif.rs`

**期待効果**: 「通常スケジューラ NIF に命令数・入力サイズ上限がない」**-3** が消える。

---

### P-12: decode エラー契約を 2 層設計に揃える

**優先度**: 中

**問題**: NIF 層の異常は `rustler::Error::Term`、VM のドメインエラーは `{:error, atom, detail}` タプルという 2 層設計自体は良い（プラス点で評価）。しかし decode 系のエラーだけがこの分類の境界を跨いでおり、Elixir 側から見て同じ失敗が経路によって異なる形で返る。エラー契約の一貫性をプロジェクトの強みとして評価している以上、ここは揃えたい。

**方針**: decode エラーを VM のドメインエラーとして `{:error, :decode, detail}` に寄せ、NIF 層の `Error::Term` は「引数の型が違う」等の呼び出し側のバグに限定する。Elixir 側のパターンマッチを 1 箇所追加する。P-11 と同じファイル群を触るため同時に行うと安い。

**対象**: `rust/nif/src/nif/formula_nif.rs`, `rust/nif/src/formula/decode.rs`, `apps/core/lib/core/formula.ex`

**期待効果**: 「decode エラー契約が非対称」**-2** が消える。

---

## 第 3 波 — 面を広げる（合計 -68）

### P-13: テスト面を広げる（-10）

**優先度**: 高（継続）

**問題**: `contents` は lib 126 ファイルに対しテスト 8 ファイル（6.3%）で、`nodes/`（40+ モジュール）・`objects/`・各 Content の playing ロジック・`FrameEncoder` の DrawCommand 変換が無検証（-3）。`render` クレートは 2729 行・client 最大規模なのに `#[test]` が 1 件もない（-2）。`rust/nif` の `#[test]` 6 件はすべて `binary_div` 関連で decode の境界条件が未検証（-1）。`apps/server/test/` は存在しない（-1）。`assets` は JWKS 取得失敗・kid ローテーション・413・同時書き込みが未検証（-2）。ゲームプレイを機械的に確認する経路もない（-1）。

**方針**: 費用対効果の高い順に着手する。(1) `FrameEncoder` は入出力が純関数に近いので golden fixture が効く。(2) `render` は `headless.rs` の PNG 出力にハッシュ比較を足せば最初の 1 本が書ける。(3) `decode_bytecode` は入力バイト列を直書きするだけで境界（途中終端・未知 opcode・レジスタ範囲外・UTF-8 不正）を突ける。(4) `apps/server` は Supervisor 起動と `:main` の Registry 登録を見る smoke test 1 本で足りる。(5) `assets` は JWKS 失敗系と 413 を先に。P-1 が済んでいれば Rust 側は自動的に CI で守られる。

**対象**: `apps/contents/test/`, `rust/client/render/`, `rust/nif/src/formula/decode.rs`, `apps/server/`（test 新設）, `assets/test/`, `rust/client/render/src/headless.rs`

**期待効果**: contents テスト密度 -3 / render 回帰テストゼロ -2 / assets テスト -2 / nif テスト偏り -1 / server テストゼロ -1 / ゲームプレイ E2E -1 の計 **-10** が消える。

---

### P-14: プロパティベース・fuzz・ベンチマーク基盤を入れる（-2）

**優先度**: 中

**問題**: StreamData / benchee / proptest / criterion のいずれも依存になく、`rust/**/benches/` は 0 ファイル。バイトコード VM・バイナリプロトコル・グラフコンパイラ・スナップショット補間という「ランダム入力と時間軸に晒される層」を 4 つ持つ構成に対し、example-based のみでは防御が薄い。

**方針**: `SnapshotInterpolator` の到着時刻・順序・欠落の組み合わせ空間が proptest の最も効く対象なので、そこから始める。次に `decode_bytecode` の fuzz、UDP `Protocol` のラウンドトリップ性質。ベンチは tick 予算 50ms に対する各処理の消費率を測る形で置く。

**対象**: `engine/rust/Cargo.toml`, `engine/mix.exs`, `rust/client/shared/src/interp.rs`, `rust/nif/src/formula/decode.rs`

**期待効果**: 「プロパティベース・fuzz・ベンチマークが全体に不在」**-2** が消える。

---

### P-15: UDP の入口防御と信頼性契約（-5）

**優先度**: 中〜高（セキュリティ）

**問題**: zlib 展開上限（64KB）は入ったが前段の防御が抜けている。ソケットは `active: true` で任意サイズを受け、JOIN はセッション数上限なしに sessions マップを増やし、登録済みセッションからの INPUT / ACTION にレート制限がない。`:action` の name も長さ上限なしで decode する（-2）。また `seq` はヘッダに存在しサーバ送信 FRAME で発行されるが受信側の INPUT / ACTION で検証されないため、古いパケットの再送・並べ替え・リプレイをそのまま受理する。FRAME は単一パケットのみで MTU 超過時の分割も再送もない（-3）。

**方針**: 前段の防御から先に入れる。(1) 生パケットサイズ上限、(2) セッション数上限、(3) セッション単位の送信レート制限、(4) `:action` name の長さ上限。次に `seq` の単調性チェック（既存 sessions マップに最終 seq を持たせるだけ）。断片化・再送は自作せず、QUIC datagram / WebTransport への載せ替えコストと比較してから決める（提案側に記載）。

**対象**: `apps/network/lib/network/udp/server.ex`, `apps/network/lib/network/udp/protocol.ex`

**期待効果**: 「UDP に生パケットサイズ・セッション数・送信頻度の上限がない」-2 と「UDP に信頼性・リプレイ・断片化の契約がない」-3 の計 **-5** が消える。

---

### P-16: ワイヤ解釈とエンドポイントの小口修正（-3）

**優先度**: 中（うち封筒形式は重要度が点数以上）

**問題**: (1) `unwrap_payload/2` がトークン検証失敗時に `len > 30` と Base64URL 文字種の正規表現で「封筒だったのか生 protobuf だったのか」を推測しており、条件が偶然噛み合えばペイロード先頭が黙って切り落とされる（-1）。(2) `GET /health` がレスポンスに `room_ids` をそのまま含め、無認証で稼働中のワールド名が偵察できる（-1）。(3) `Network.S2S.Client` が peer URL のスキームを制限せず `http://` でも取得を試みる（-1）。

**方針**: (1) 封筒にマジックバイト + バージョンを付けて確率的推測をなくす。ワイヤ変更なので生 protobuf との併存期間を設ける。(2) `/health` は件数のみ返し、一覧は S2S / 管理エンドポイントへ移す。(3) S2S クライアントは既定で `https` のみ許容し、開発時のみ明示的な設定で `http` を許す。

**対象**: `apps/network/lib/network/room_auth.ex`, `apps/network/lib/network/router.ex`, `apps/network/lib/network/s2s/client.ex`

**期待効果**: 封筒ヒューリスティック -1 / `/health` のルーム ID 公開 -1 / S2S 平文 HTTP 許容 -1 の計 **-3** が消える。静かにペイロードが壊れる種類のバグは発見が最も遅れるため、(1) は点数以上に優先する。

---

### P-17: contents の掃除（-6）

**優先度**: 中

**問題**: (1) `objects/core/` の 4 ファイルが TODO スタブで、`MenuComponent` は実装を持つがどの Content にも登録されていない（-3）。(2) `apps/contents/mix.exs` に `{:network, in_umbrella: true}` が残り contents 単体のビルド・テストができない（-1）。(3) `Device.Helpers` の 1 引数版が `:main` に委譲しており、非 `:main` ルームで静かに誤ったルームを触る（-1）。(4) 撤去済み NIF frame injection のコードが毎フレームの経路に残っている（-1）。

**方針**: (1) はスタブを実装するか、実装予定がないなら削除して「動く実装」と「動かない実装」を同じ名前空間に置かない。`MenuComponent` は登録するか外す。(2) は `FrameEncoder` が必要とする型を `core` か新設の共有アプリへ寄せる。(3) は 1 引数版を廃止して `room_id` 必須にする（P-7 と同時に行うのが自然）。(4) は削除する。

**対象**: `apps/contents/lib/objects/core/`, `apps/contents/lib/components/category/ui/menu_component.ex`, `apps/contents/mix.exs`, `apps/contents/lib/components/category/device/helpers.ex`, `apps/contents/lib/events/game.ex`

**期待効果**: スタブ残存 -3 / network コンパイル時依存 -1 / `Helpers` の `:main` 固定 -1 / 死にコード -1 の計 **-6** が消える。なお `Tetris` の固定 60Hz は費用対効果が大きいため P-6 として第 1 波に切り出してある。

---

### P-18: core の掃除（-6）

**優先度**: 中

**問題**: (1) `NifBridge.Behaviour` は定義のみで `Core.Formula.run/3` が実 NIF を直呼びするため、NIF ビルドなしで core のテストが回らない（-2）。(2) `:formula_store_synced` ETS がプロセス所有の明示なく作られ、所有者が落ちた場合の再作成・引き継ぎが設計されていない（-2）。(3) `Core.Telemetry` に `game.tick.enemy_count` 等の BulletHell 固有語彙が残る（-1）。(4) `Core.Component` の moduledoc が撤去済みの 60Hz 物理ループと `world_ref` を説明している（-1）。

**方針**: (1) config 注入 + Mox を入れる。純 Elixir 参照 VM を用意すると differential テストにも使えるが、そこは提案側の範囲。(2) `FrameCache` が持つ「ETS 所有者をルームより先に起動してアプリ寿命で保持する」という既存の規律をそのまま適用する。(3) メトリクス定義をコンテンツ側へ移す。`Core.Config` / `StressMonitor` / `Stats` の語彙分離は完了済みで残渣はここだけである。(4) moduledoc を現行の権威 tick 前提に書き直す。

**対象**: `apps/core/lib/core/nif_bridge_behaviour.ex`, `apps/core/lib/core/formula.ex`, `apps/core/lib/core/formula_store.ex`, `apps/core/lib/core/telemetry.ex`, `apps/core/lib/core/component.ex`

**期待効果**: `NifBridge.Behaviour` 未配線 -2 / `FormulaStore` の ETS 非所有 -2 / `Core.Telemetry` の残存語彙 -1 / `Core.Component` の moduledoc -1 の計 **-6** が消える。moduledoc の誠実さはプロジェクトの強み（+3）なので、中心ビヘイビアの記述ずれは点数以上に目立つ。

---

### P-19: auth の残課題（-8）

**優先度**: 中（2026-08-01 以降 `lib/` 変更ゼロで、前回指摘が全件存続）

**問題と方針**:

| 項目 | 点 | 方針 | 対象 |
|:---|:---:|:---|:---|
| メール未検証でも JWT を発行する | -2 | `login/3` と register 後の `issue_session` に `email_verified_at` のゲートを入れる。検証フロー自体は完成しているのに、どの認証経路にも効いていない | `auth/lib/auth/accounts.ex` |
| 最低年齢ポリシーがない | -1 | `BirthdayInPast` に最低年齢の検証を足す。年齢レーティングを S2S で公開する設計を持つなら入口の確認は必須 | `auth/lib/auth/accounts/validations/birthday_in_past.ex` |
| `/health` に DB readiness がない | -1 | DB 疎通を含めて 503 を返せるようにする。`assets` の `/health` も同様 | `auth/lib/auth_web/controllers/health_controller.ex` |
| `account_tokens` の GC が対象外 | -1 | `TokenCleanup` の削除対象に `AccountToken`（`expires_at` / `used_at`）を加える | `auth/lib/auth/token_cleanup.ex` |
| レート制限が単一ノード ETS | -1 | 水平スケール時に備え、バックエンドを差し替え可能にする（当面は据え置きでも可） | `auth/lib/auth/rate_limit.ex` |
| CORS allowlist がない | -1 | `Corsica` を入れて allowlist を設定する。SPA・管理画面を足す時点で必要になる | `auth/lib/auth_web/endpoint.ex` |
| Dialyzer / 依存監査がない | -1 | `dialyxir` / `mix_audit` を deps と `precommit` に追加する | `auth/mix.exs` |

**期待効果**: 計 **-8** が消える。メール検証ゲート以外はいずれも 1 行〜数十行で埋まる。

---

### P-20: assets の堅牢化（-4）

**優先度**: 中

**問題**: (1) `Assets.Objects.put/4` がファイル書き込みと `AssetMetadata` の upsert を別々に行い、トランザクション境界がない。片方だけ成功すると孤児ファイルまたは実体のないメタデータが残る（-2）。(2) 書き込み回数の制限とユーザー単位の総容量クォータがなく、1 アカウントでスロットを変えながら書き込めばディスクを埋められる（-1）。(3) ストレージがローカルディスク単一アダプタで、複数ノード運用時に共有ストレージへ差し替えられない（-1）。

**方針**: (1) 「メタデータを pending で作る → BLOB を temp へ書く → atomic rename → メタデータを確定」の 2 相方式に整える。孤児の照合は提案側の reconciler に任せる。(2) auth が 12 バケットの多軸レート制限を持つので同型を適用し、あわせてユーザー単位のクォータを持つ。(3) `Assets.Storage` の Behaviour は既にあるため、S3 互換アダプタを 1 つ足して抽象が実際に機能することを示す。

**対象**: `assets/lib/assets/objects.ex`, `assets/lib/assets_web/controllers/object_controller.ex`, `assets/lib/assets/storage/`

**期待効果**: 非アトミック -2 / クォータ欠如 -1 / 単一アダプタ -1 の計 **-4** が消える。

---

### P-21: クライアント体験と境界（-9）

**優先度**: 中

**問題**: (1) `predict_input` が「入力をそのまま返す」スケルトンのままで、権威 20Hz + 遅延バッファ 80〜250ms により自機移動に 100ms 超の体感遅延が乗る（-2）。(2) 補間のエンティティ対応付けが安定 ID でなく距離 3.0 以内の最近傍で、高速移動・高密度・テレポートでは誤対応が原理的に避けられない（-2）。(3) `platform/web.rs` は全メソッドが未実装を返すスタブ（-2）。(4) フラスタム・距離カリングがなく、SE も `Sink::connect_new` + `detach()` で同時再生数の上限がない（-1）。(5) `sample()` が毎フレーム `RenderFrame` をフル複製している（-1）。(6) `network` クレートが `render` / `audio` に依存しており、クレート境界の明快さ（+4）に対する例外になっている（-1）。

**方針**: (2) を先に行う。`entity_id` を protobuf に 1 フィールド足し、「ID があれば ID、なければ近傍」の段階移行にすれば、誤対応と O(n²) が同時に解消する。次に (1) の予測を `predict.rs` に本実装する（入力に `seq` があるのでサーバ側 ack と reconciliation の 2 点で成立）。(5) は `Arc<RenderFrame>` の導入。(6) は `RenderFrame` 型と audio cue を `shared` へ寄せる。(3) は当面やらないなら `cfg` で切ってロードマップ側に置くほうが読み手を誤らせない。(4) はフラスタムカリングと SE ボイス上限。

**対象**: `rust/client/shared/src/predict.rs`, `rust/client/shared/src/interp.rs`, `3rdparty/alchemy-protocol/proto`, `apps/contents/lib/contents/frame_encoder.ex`, `rust/client/network/src/platform/web.rs`, `rust/client/network/Cargo.toml`, `rust/client/render/`, `rust/client/audio/src/audio.rs`

**期待効果**: 予測未配線 -2 / 近傍マッチ -2 / WASM スタブ -2 / カリング・SE 上限 -1 / 毎フレーム clone -1 / `network` 逆依存 -1 の計 **-9** が消える。

---

### P-22: 可観測性を外部化する（-2）

**優先度**: 中

**問題**: engine 全体の `:telemetry.execute` は 3 箇所のみ（`[:game, :session_end]` / `[:game, :tick]` / `[:game, :frame_dropped]`）で、`Core.Telemetry` は `ConsoleReporter` どまり。この 3.5 週間で入った層（JWKS 検証・S2S peer 取得・UDP セッション淘汰・Zenoh 再接続・補間の遅延適応）に telemetry イベントが 1 つも追加されていない。補間の適応遅延はユーザーが「重い」と言ったときに実測値がないと切り分け不能である。

**方針**: 新規層それぞれに telemetry イベントを足したうえで、`ConsoleReporter` を PromEx / OTel exporter に差し替える。補間の内部状態（適応遅延・観測間隔 EMA・キュー枚数・playback-ahead クランプ）はデバッグ HUD にも出す（提案側に記載）。

**対象**: `apps/core/lib/core/telemetry.ex`, `apps/network/lib/network/{auth_verifier,zenoh_bridge}.ex`, `apps/network/lib/network/udp/server.ex`

**期待効果**: 「telemetry が ConsoleReporter 止まり」**-2** が消える。

---

### P-23: 配布形態を確定する（-4）

**優先度**: 中〜低（ただし連合構想の前提）

**問題**: (1) ルート `mix.exs` と `apps/server/mix.exs` の双方に `releases:` がなく、配布・デーモン化手段が `mix run --no-halt` のみ。auth と assets は `mix release` + Dockerfile を持つため engine だけが取り残されている（-2）。(2) `ci.yml` は全ジョブ `runs-on: ubuntu-latest` で、クライアントの Windows / macOS 固有分岐（Credential Manager / Keychain / Secret Service）が一度も検証されない。インストーラ・自動更新も未着手（-2）。

**方針**: (1) auth / assets の `mix release` + 3 ステージ Dockerfile がそのまま雛形になる。(2) CI に Windows / macOS のマトリクスを足す。まずは `cargo check` + テストのみで、GPU を要する経路は除外する。インストーラ（MSIX / notarized dmg）と SBOM は提案側に記載した。

**対象**: `mix.exs`, `apps/server/mix.exs`, `.github/workflows/ci.yml`

**期待効果**: engine の release 定義なし -2 / CI 単一 OS -2 の計 **-4** が消える。連合として他運営者にサーバを立ててもらう構想は、配布形態がないと始まらない。

---

### P-24: ゲームプレイの物量（-5）

**優先度**: 低〜中（設計上の障害はなく物量の問題）

**問題**: 開始 → プレイ → 終了 → リトライが閉じているのは `Tetris` と `BulletHell3D` の 2 本のみで、残り 3 本はデバッグ・検証用（-3）。既定に近い `BulletHell3D` はタイトル画面なし・敵種 1 種・プレイヤーの攻撃手段なし・単一アリーナ。アセットは音声 6 ファイルと atlas 1 枚で、ゲーム別ディレクトリは `.gitkeep` のみ、設定 UI もない（-2）。

**方針**: `BulletHell3D` に攻撃手段・敵種・wave 構成・タイトル画面を足す。パラメータ外部化（`FormulaStore` / コンポーネント注入）が既にあるため追加要素の大半はデータで表現できる。アセットはソース・ライセンス・atlas manifest を持つ再現可能なパイプラインに置き換える（提案側に記載）。P-9 が済んでいればセーブも載る。

**対象**: `apps/contents/lib/contents/bullet_hell_3d/`, `engine/assets/`

**期待効果**: 実ゲームが 2 本 -3 / 視覚アセットが極薄 -2 の計 **-5** が消える。「外部の人に渡して 10 分遊べる」状態が目標である。

---

### P-25: 分散と連合の次段（-4）

**優先度**: 低（構想上は中心だが、現状は前提が揃っていない）

**問題**: (1) `find_room_node` が毎回 `cluster_nodes()` への `:rpc` 逐次スキャンで、コード内コメント自身が改善余地を認めている。`list_rooms_clustered/0` も同様（-2）。(2) read-only S2S は着地したが、ActivityPub / WebFinger / インスタンス間 identity federation はソース上ゼロで、S2S 自体も既定オフ。訪問トークンやアバター持ち出しといった「連合の本体」は未着手（-2）。

**方針**: (1) `:global` レジストリまたは永続的な配置テーブルでキャッシュする。「1000 人規模」を掲げるならノード数 × 呼び出し頻度に線形劣化する経路は先に潰す。(2) 訪問トークン（他インスタンスのユーザーが自分のワールドに入れる）が次の一歩で、`Network.S2S.Instance` の署名と `Network.AuthVerifier` の JWKS 検証という部品はすべて揃っている。P-8 で `RoomToken` に `sub` が入っていることが前提になる。

**対象**: `apps/network/lib/network/distributed.ex`, `apps/network/lib/network/s2s/`, `config/config.exs`

**期待効果**: ルーム所在解決の RPC スキャン -2 / 連合が read-only カタログ止まり -2 の計 **-4** が消える。

---

## 前版（2026-04-01）からの引き継ぎ

前版の D-1〜D-7 は Fable 単独評価を前提としていた。現在の状況は次のとおりである。

| 旧 ID | 論点 | 現在 |
|:---|:---|:---|
| D-1 | `Network.UserSocket` の moduledoc | **対応済み**（2026-04-01）。今回の評価でも指摘なし |
| D-2 | オンライン永続化 ADR | **前提が変わった**。`assets` サービスが実在するため ADR ではなく配線が課題。**P-9** に置き換え |
| D-3 | 単一 CI エントリ | **達成済み**。`mix alchemy.ci` が 23 秒で ALL PASSED。残るのは対象範囲（**P-1**）と文書整合（**P-4**） |
| D-4 | `Server.Application` の smoke テスト | **未着手のまま存続**。**P-13** に統合 |
| D-5 | Diagnostics のコンテンツ非依存化 | **ほぼ解消**。`FrameCache` の語彙整理が完了し、残渣は `Core.Telemetry` のみ。**P-18** に統合 |
| D-6 | ランチャー（`rust/launcher`） | **リポジトリ外へ分離済み**。配布の論点は **P-23** に移動 |
| D-7 | `Core.InputHandler` の残骸 | **削除済み** |

また、前版のスコアカードが参照していた「採点式合計 +33 点（2026-04-01）」および 2026-03 系の前提記述は、本版で 2026-08-25 のまとめ評価に全面的に置き換えた。

## 関連リンク

- [docs/warranty/ci.md](../../docs/warranty/ci.md) — ローカル CI（`mix alchemy.ci`）の定義
- [docs/architecture/overview.md](../../docs/architecture/overview.md)
- [docs/cross-compile.md](../../docs/cross-compile.md)
- [workspace/README.md](../README.md) — レーン運用
