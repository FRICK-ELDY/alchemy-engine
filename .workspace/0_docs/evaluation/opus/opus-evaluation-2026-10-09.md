# AlchemyEngine 評価レポート（Opus / 2026-10-09）

## 評価者と方法

- **評価者**: Claude Opus 5.5（第1評価者）。他の評価者とは協調せず独立に評価した。GPT 系の評価ファイルと、本日付の他のファイルは読んでいない。
- **準拠ルール**: ルートの `.cursor/rules/evaluation.mdc`。`world-server/.cursor/rules/evaluation.mdc` は古いため使っていない。
- **前回資料の扱い**: `archive/` にある 2026-08-25 の総合まとめ（weaknesses / strengths / proposals / evaluation）と、自系統の前回詳細 `opus/archive/2026-08-25/` は「再検証すべき主張の一覧」としてだけ使った。点数は一切引き継いでいない。`.workspace/0_reference/improvement-plan.md` は計画の文脈として参照し、各項目が消化されたかを現行ソースで確かめた。
- **評価の根拠**: 自分で開いた現行ソースのみ。各詳細ファイルの行番号は今回読んだものである。

### 実行したこと

それぞれ `%TEMP%` 配下の専用 `CARGO_TARGET_DIR` で実行し、他のビルドのロックと競合しないようにした。

| コマンド | 結果 |
|:---|:---|
| `client`: `cargo test -p shared` | 18 passed |
| `client`: `cargo test -p network --test render_frame_e2e_contract` | 1 passed |
| `world-server/rust`: `cargo test -p nif` | 6 passed |

### 実行していないこと

- `mix alchemy.ci`（全体）。ビルドロックの競合を避けるという指示に従った。代わりに `alchemy.ci.ex` と各 `.github/workflows/*.yml` を読んで CI の範囲を確認した。
- `mix test`（world-server・auth-server とも）。テスト数は `test` マクロを数えたもので、通過は確認していない。
- 上記以外の client クレートのテスト、`cargo clippy`、`mix credo`。
- GitHub Actions の実行結果、ブランチ保護、`gh` による PR / CI 状況の確認。このため「CI が実際に緑か」「CI を必須にしているか」は評価していない。
- 実機でのクライアント起動、zenohd との結合、VR ランタイムでの動作。

---

## 観点別の集計

| 観点 | プラス | マイナス | 差し引き |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ・ビジョン） | +16 | -13 | **+3** |
| world-server — apps/contents | +28 | -26 | **+2** |
| world-server — apps/core | +22 | -6 | **+16** |
| world-server — apps/network | +30 | -19 | **+11** |
| world-server — apps/server | +4 | -6 | **-2** |
| world-server — rust/nif（Formula VM。physics は撤去済み） | +13 | -6 | **+7** |
| client（shared / network / render / window / audio / app） | +44 | -21 | **+23** |
| auth-server（lib/auth / lib/auth_web） | +60 | -11 | **+49** |
| 横断評価層（テスト・可観測性・エラー処理・変更容易性・DX・セキュリティ・全体設計） | +23 | -23 | **0** |
| **総計** | **+240**（94 項目） | **-131**（70 項目） | **+109** |

提案は 18 項目（すべて 0 点）。

client の内訳: shared +5 / -5、network +7 / -5、render +9 / -3、window +2 / 0、audio +6 / -1、app・その他 +15 / -7。
auth-server の内訳: lib/auth +40 / -8、lib/auth_web +20 / -3。

### 前回（Opus 2026-08-25）との数値比較

| | 2026-08-25 | 2026-10-09 | 差 |
|:---|:---:|:---:|:---:|
| プラス | +257 | +240 | -17 |
| マイナス | -69 | -131 | -62 |
| 総計 | +188 | +109 | -79 |

総計が 79 点下がった内訳は 3 つある。(1) `assets` サービスがスーパープロジェクトから外れ、その純寄与（約 +7）が対象外になった。(2) 前回の第1評価者（自分）が見落としていた欠陥を今回新たに検出した（約 -30）。(3) 前回は総合まとめ側でだけ計上されていた欠陥を、今回は自分でコードを確認して計上した（約 -35）。**コードが前回より悪くなったわけではない。** この 45 日間、ソースはほとんど変わっていない。点数が下がったのは、前回の Opus 評価が甘かったことの補正という面が大きい。

---

## 2026-08-25 からの変化（コードで確認したもの）

### 解消されたもの

**実質的になし。** 前回の改善計画の第 1 波 6 件（クライアントテストの CI 化、prod 認証の fail-secure、Elixir 側 Zenoh の再接続、保証文書の追従、依存監査、Tetris の dt 化）を 1 件ずつ現行ソースで確認したが、どれも手が付いていない。

構造面では次の変化があった。いずれも欠陥の解消ではなく、新しい長所として計上している。

- 4 リポジトリ（`world-server` / `client` / `auth-server` / `protocol`）への分割と、`PROTOCOL_PIN` の sha 検証付き解決（+3）
- protocol リポジトリ単体のコンパイル CI（+1）
- `world-server` から client クレートが抜け、Rust ワークスペースが `nif` だけになったこと（依存の見通しが良くなった）

### 継続しているもの（主なもの）

| 項目 | 点数 | 根拠 |
|:---|:---:|:---|
| シーンスタックが全ルームで共有 | -4 | `server/application.ex:25`、5 コンテンツの `flow_runner/1` |
| OpenXR が app に未配線 | -4 | `client/app/src/main.rs` に xr の参照なし |
| クライアントの 52 テストが CI で動かない | -3 | `client/.github/workflows/ci.yml` に `cargo test` なし |
| `AUTH_REQUIRED` が prod でも既定 false | -3 | `world-server/config/config.exs:57`、`runtime.exs` |
| `RoomToken` に `sub` がない | -3 | `network/room_token.ex:33-37` |
| Elixir 側 `ZenohBridge` に再接続がない | -3 | `zenoh_bridge.ex:52-84` |
| save / load 未配線 | -3 | `events/game.ex:106-117` |
| VM に命令数上限がなく、DirtyCpu でもない | -3 | `decode.rs:53-171`、`formula_nif.rs:26` |
| 保証文書の乖離 | -3 | `ci.md:10,13,46,48` |
| 完結したゲームは 2 本 | -3 | `contents/` |
| Tetris が 60Hz 固定 | -2 | `tetris/playing.ex:10,13` |
| 依存監査なし | -2 | 4 リポジトリとも `dependabot.yml` なし |

### 新たに検出したもの

| 項目 | 点数 | 根拠 |
|:---|:---:|:---|
| 任意のクライアントが `"__quit__"` でサーバを停止できる。既定コンテンツの Quit ボタンでも起きる | -4 | `keyboard.ex:55-58,73`、`game.ex:280-288`、`sample_osc/playing.ex:238` |
| 「binary64 の 3D 座標系」の主張に対し、ワイヤは全座標 binary32 | -4 | `README.md:5`、`vision.md:12`、`draw_commands.proto:27` |
| `Events.Game` に catch-all がなく、非 binary の action 名でルームが落ちる | -3 | `game.ex:103`、`channel.ex:133-139` |
| リポジトリ横断の検証がない（ピンの重複、golden の照合不能） | -3 | 2 つの `PROTOCOL_PIN`、スーパープロジェクトに `.github` なし |
| 公式クライアントが RoomToken を使わず、認証付きサーバに入れない | -3 | `network_render_bridge.rs:125-166` |
| `RoomSupervisor` 再起動後に `:main` が復元されない | -2 | `server/application.ex:35-43` |
| refresh token ローテーションの競合 | -2 | `accounts.ex:115,307,360-372`、`refresh_token.ex:75-77` |
| ローカル CI の入口が world-server にしかない | -2 | `alchemy.ci.ex:93-107` |
| ビジョンが「物理の基盤」を保証項目に挙げるが、物理がない | -2 | `vision.md:27` |
| 改善サイクルが止まっている | -2 | `improvement-plan.md:59-143` |

新規のうち `"__quit__"`・catch-all 欠如・`:main` 非復元の 3 件は組み合わさる。**認証オフの既定設定なら、ネットワーク上の誰でも数メッセージで `:main` を恒久的に消すか、ノードごと停止できる。** また、既定コンテンツ（`SampleOsc`）の HUD にある「Quit」ボタンは `"__quit__"` を送るので、悪意のない 1 人のプレイヤーでも全員のサーバを止められる。今回の評価で最も優先度の高い修正対象である。

---

## 長所の上位 5 件

1. `SnapshotInterpolator`（ジッタに応じた適応的な補間遅延、テスト 18 件 pass）`+5`
2. auth-server の RS256 複数鍵 JWKS とローテーション `+5`
3. NIF を Formula VM に絞り、物理・SoA・SIMD を撤去した判断 `+4`
4. `Core.FormulaGraph`（DAG → バイトコードのコンパイラ、循環検出付き）`+4`
5. メールボックス深さによるバックプレッシャーとフレームドロップ telemetry `+4`

同点の次点: 3 トランスポートの収束（+4）、クライアントの Zenoh 再接続（+4）、`auth_client` の OS キーリング保存（+4）。

## 弱点の上位 5 件

1. 任意のクライアントが `"__quit__"` でサーバプロセスを停止できる `-4`
2. 「binary64 の 3D 座標系」の主張と、binary32 のワイヤ契約の矛盾 `-4`
3. シーンスタックが全ルームで共有されている `-4`
4. OpenXR が出荷 app に未配線 `-4`
5. 同点 -3 の群: `Events.Game` の catch-all 欠如、`AUTH_REQUIRED` 既定オフ、`RoomToken` に `sub` なし、公式クライアントの RoomToken 未配線、リポジトリ横断検証の不在、クライアントテストの CI 未実行

---

## 観点別の所見

### world-server

core（+16）と network（+11）は堅い。FormulaGraph とバイトコード契約、3 トランスポートの収束、zlib 上限・atom 枯渇対策といった防御は、同規模の OSS ではなかなか見ない水準である。一方 contents（+2）は、良い部品（バックプレッシャー・dt・MFA 注入）を持ちながら、マルチルームの状態分離とリモート入力への耐性が欠けている。どちらも「マルチプレイヤーのサーバ」としての前提に関わる欠陥である。server（-2）は release がなく、`:main` の復元もできない。nif（+7）はエラー境界が模範的な一方、VM としての資源制限がない。

### client

+23。`SnapshotInterpolator`・再接続・キーリング保存は製品品質に近い。予測が空、対応付けが近傍頼み、render のテストがゼロ、VR が起動しない、という点で「VR 対応のネットワーククライアント」としての完成度はまだ半分程度である。CI がテストを実行しないので、今ある 52 件のテストも回帰を防げていない。

### auth-server

+49。4 リポジトリで最も完成度が高い。鍵ローテーション・family ローテーション・Argon2・ハッシュ保存・レート制限・107 テスト・release と、Phoenix / Ash の定石を外さずに運用まで見据えている。refresh の競合とメール検証ゲートの欠如が残るが、どちらも局所的に直せる。問題は auth-server 単体ではなく、**world-server の公式クライアントがこの認証を使う経路を持たない**ことにある。

### 横断

差し引き 0。テストの層分け・`mix alchemy.ci`・proto-verify は良い。ただし分割後は、品質の入口が world-server の中にしかない。保証文書は分割前の構成（physics・bench）を説明したままで、評価ルール自体も physics を前提にしている。

---

## 総評

**AlchemyEngine は部品の品質が高く、統合の品質が低い。今回のリポジトリ分割で、その差がさらに開いた。**

部品単位で見ると、`SnapshotInterpolator`、auth-server の鍵・トークン管理、FormulaGraph、トランスポートの収束とバックプレッシャーは、Bevy や Godot のエコシステムで見かける同種の実装と比べても劣らない。NIF から物理を撤去して Elixir を唯一の権威に据えた判断も一貫している。

一方、部品同士の繋ぎ目には次の穴がある。

- 認証サービスは完成しているのに、公式クライアントがそれを使って入室できない。
- サーバはルームを分離するのに、シーンスタックは共有されている。
- golden 契約テストはあるのに、生成する側が照合しない。
- 「binary64 の座標系」を一行要約に掲げているのに、ワイヤは binary32。
- ネットワークから届く 1 つの文字列でノードが止まる。

これらはどれも、個々のリポジトリの CI では検出できない種類の欠陥である。4 リポジトリに分けた今、統合の検証を担う場所がどこにもない。

この 45 日間はリポジトリ分割に費やされ、前回の改善計画の第 1 波は 1 件も消化されなかった。分割自体は正しい方向だが、分割の価値は「横断の検証」とセットで初めて出る。

次のサイクルで最初にやるべきことは、この順に 4 つである。

1. ネットワーク由来 UI action の許可リストと、`Events.Game` の catch-all。数十行で済み、最も重い 2 件を消せる。
2. client CI への `cargo test --workspace` の追加。1 行で済む。
3. スーパープロジェクトの integration CI。ピンの一致・golden の再生成と照合・認証付き smoke test。
4. binary64 の文言を、実装に合わせて書き分けるか、浮動原点の設計に着手するかの決定。

**総計 +109（+240 / -131）。** 前回の自評価 +188 より大きく下がったが、主因はコードの劣化ではなく、前回見落とした欠陥の計上である。

---

## 詳細ファイル

- マイナス点: `.workspace/0_docs/evaluation/opus/opus-specific-weaknesses-2026-10-09.md`
- プラス点: `.workspace/0_docs/evaluation/opus/opus-specific-strengths-2026-10-09.md`
- 提案: `.workspace/0_docs/evaluation/opus/opus-specific-proposals-2026-10-09.md`
