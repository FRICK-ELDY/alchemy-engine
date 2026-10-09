# AlchemyEngine 総合評価 — GPT-5.6 Sol（2026-10-09）

## 評価者

- 第2独立評価者: **GPT-5.6 Sol**
- 評価日: 2026-10-09
- 対象: `world-server/`、`client/`、`auth-server/` と横断設計
- 独立性: `opus/` 配下および他評価者の2026-10-09文書は参照していない。2026-08-25まとめと改善計画は、現行コードで再検証するためのチェックリストとしてのみ使用した。

## 方法

評価ルールの全20観点について、現行ソース、test配置、4つのworkflow、`mix alchemy.ci` 実装、CI保証文書、visionを直接読んだ。前回項目は、対象コードを再読できたものだけ「解消/継続」と判定した。

ビルド競合を避けるという依頼に従い、**full `mix alchemy.ci` は実行していない**。また、cargo/mix test、clippy、format、credo、workflow実行も行っていない。したがって本評価が保証するのは静的なコード・設定・test配置の評価であり、2026-10-09 HEADの実行時成功やCI greenではない。

## スコア

| 観点 | プラス | マイナス | 総合 |
|:---|---:|---:|---:|
| world-server/apps/contents | +10 | -8 | +2 |
| world-server/apps/core | +10 | -4 | +6 |
| world-server/apps/network | +10 | -12 | -2 |
| world-server/apps/server | +2 | -3 | -1 |
| world-server/rust/nif（physics含む） | +5 | -9 | -4 |
| client/shared | +8 | -5 | +3 |
| client/network | +8 | -6 | +2 |
| client/render | +7 | -3 | +4 |
| client/window | +3 | -1 | +2 |
| client/audio | +3 | -2 | +1 |
| client/app | +2 | -3 | -1 |
| auth-server/lib/auth | +13 | -4 | +9 |
| auth-server/lib/auth_web | +7 | -2 | +5 |
| テスト戦略 | +3 | -6 | -3 |
| 可観測性・デバッグ容易性 | +2 | -3 | -1 |
| エラーハンドリング戦略 | +3 | -2 | +1 |
| 変更容易性・保守性 | +4 | -2 | +2 |
| 開発者体験（DX） | +5 | -5 | 0 |
| セキュリティ・配布可能性 | +5 | -3 | +2 |
| プロジェクト全体設計 | +6 | -7 | -1 |
| **合計** | **+116** | **-90** | **+26** |

項目数: プラス36 / マイナス34 / 提案20。

## 観点別評価

### world-server/apps/contents

Content/Scene/Component境界、Elixirでのrule/mesh/UI定義、複数content実装は強い。一方、全roomが単一Scene Stackを共有するため、最重要の状態所有境界が成立していない。Tetrisの60Hz固定とsave/load・object編集スタブも、visionの「権威tick」「作りながら遊ぶ」に反する。**設計の器は良いが、room単位の実体が未完成**である。

### world-server/apps/core

DynamicSupervisor、RoomRegistry、FormulaGraph、backpressureは良い。ただしroom supervisorが管理するのはtick GenServerだけでscene stateはglobal、FormulaStore ETS所有者も不定である。Component docsとTelemetryに旧world_ref/NIF/敵・boss語彙が残り、coreの汎用性を弱める。

### world-server/apps/network

Local/Phoenix/UDP/Zenoh、JWKS verifier、分散RPC、S2S catalogまで面は広い。AuthVerifierのclaims検証は高品質である。しかしprodも認証既定off、RoomTokenに`sub`なし、server Zenoh再接続なし、UDP入口防御なしで、**transportの数に対して運用保証が追いついていない**。Phoenix Channelのようにtransportを増やす前にidentityとrecoveryを一つの契約へ固定すべき段階である。

### world-server/apps/server

必須contentとsecretのfail-fastは良い。一方、application rootがglobal scene/event/statsを一個ずつ起動する構造自体がmulti-room不具合の起点であり、release/smoke testもない。

### world-server/rust/nif（physics含む）

Formula VMへ縮小した判断は、NIF障害面を小さくする意味では正しい。算術panicもテストされる。しかし評価ルールとvisionが保証対象にするphysics/ECS/SoA/SIMD/衝突は現行sourceに存在しない。さらにuser-defined bytecodeを通常schedulerで無制限decode/runする。**小さなVMとしては良いが、物理エンジンとして採点できる実装はゼロ**である。

### client/shared

SnapshotInterpolatorは本repoで最も優れた実装である。ジッター、burst、gap、out-of-order、audio一回性まで18 testで扱う。一方、server tick/entity IDがなく最近傍O(N²)推測に依存し、predictionは恒等関数である。次の改善はアルゴリズムの微調整ではなくwire契約拡張である。

### client/network

Zenoh clientのpublisher cache、generation付きreconnect、lock外I/O、容量1 ringは非常に良い。しかし出荷clientはauth UIのtokenをRoomToken/envelopeへ接続せず、`AUTH_REQUIRED=true`のserverへinputを送れない。Web実装も常にerrorのstubである。**回線復旧は強いが、認証済みsession成立が欠ける**。

### client/render

wgpu 2D instancing、3D、egui、content WGSL、headless PNG rendererを持ち、個人projectとして十分に高い。ただしgame固有内訳から固定capacityを決め、culling/drop telemetry/render regression testがない。Godot/Bevy級と比べるとrender graph、resource lifetime、visibility phaseがまだ一枚岩である。

### client/window

ESC/system menu/input suppression/focus loss/cursor復帰の状態遷移は丁寧である。GPU/window初期化の`expect`だけはdesktop製品境界として改善余地がある。

### client/audio

専用threadとdevice不在fallbackは良い。無界channel、無制限detached Sink、priority/voice limit/spatial audio不在のため、visionがいう3D audio基盤には届いていない。

### client/app

mainは薄くcrate統合に徹する。ただしlogin、room token、network envelopeがつながらず、XRも出荷entryから選べない。各部品が存在することと、ユーザー経路が閉じることを区別すべきである。

### auth-server/lib/auth

今回最も完成度が高い領域である。Argon2、RS256 multi-key JWKS、revocation、refresh family rotation/reuse detection、row lock付きverify/reset、全refresh失効が揃う。Phoenix標準生成認証より強い。ただしemail verificationがtoken発行を制約せず、作り込んだverification flowが認可上無効になっている点は重い。

### auth-server/lib/auth_web

router pipeline、Authenticate failure分類、多軸rate limit、列挙安全な応答が明快である。healthはDB readinessを見ず、CORS方針もない。API境界は良いがproduction probe/ブラウザ境界が不足する。

### テスト戦略

重要な時間軸・wire・securityのtestはある。しかしclientの61 testをclient CIが一件も実行せず、world-server CIはNIFだけをcargo testする。auth-serverは現在`use ExUnit.Case`を持つtest fileが2本しかなく、前回まとめが記録した107 testから大幅に縮小している。property/fuzz/bench、render golden、認証付きapp E2Eもない。**良いtestコードを持つが、品質ゲートとして成立していない**。

### 可観測性・デバッグ容易性

auth failure/rate-limitのstructured logは良い。world-serverはConsoleReporter、clientはlog中心で、再接続・interpolation・UDP・GPU/audio dropを横断追跡できない。1000人/連合を掲げるならOTel traceとroom/tick相関IDは必須である。

### エラーハンドリング戦略

malformed input、audio device、surface loss、JWKS refreshに局所fallbackがある。一方、silent drop、panic初期化、server Zenohの半死状態が混在し、retryable/degraded/fatalの分類が共通化されていない。

### 変更容易性・保守性

superproject、独立repo、protocol SSoT、contents/core境界は変更範囲を予測しやすい。反面、`native/...` header、旧60Hz/NIF docs、disabled TODO lint、dead injection pathが現状理解を汚す。移行の履歴を現役sourceに残し過ぎている。

### 開発者体験（DX）

Quick Startと子repo CI、world-serverの`mix alchemy.ci`は良い。しかし保証文書は廃止済みroot workflowとphysics jobを説明し、単一entryもclient/auth/protocolを含まない。今回は指示どおりfull CIを走らせていないため、エラーゼロ通過は確認していない。

### セキュリティ・配布可能性

authの鍵管理、world-server secret fail-fast、JWKS claim検証は強い。依存脆弱性監査、3OS matrix、client署名配布、SBOM/provenance、world-server releaseがない。authだけが配布単位として先行している。

### プロジェクト全体設計

「Elixir=authority、Rust=experience」「domain SSoTとwire SSoTの分離」は明快で、多くのcodeが従う。しかし最上位保証のbinary64 3Dはclient f32契約と矛盾し、physics基盤、Hub、realtime editing、認証付きroom参加がvertical sliceとして存在しない。**visionの文章品質に実製品経路が追いついていない**。

## 2026-08-25との比較

### 解消・前進を現行コードで確認

- **repo layoutと評価ルールの更新**: 現在は`world-server/`、`client/`、`auth-server/`を正しく対象化し、旧`engine/rust/client`前提はroot ruleから消えた。
- **子repo CIの有効化**: world-server/client/auth/protocolに有効なworkflowが存在する。前回のroot workflow無効化問題はrepo分割後の形で解消した。ただしclient test未実行は別問題として残る。
- **auth account lifecycleの拡張**: email verification、password reset、change password、deactivateがtransactionとtoken失効を伴って実装されている（`accounts.ex:156-273`）。
- **client reconnectの成熟**: generation gate、lock外close/put、再購読まで現行コードで確認した（`client/network/src/platform/desktop.rs:250-376`）。
- **client test数の増加**: 現行clientには61 testがある。前回52から増えたがCIには載っていない。

### 依然未解決

- global `Contents.Scenes.Stack` とroom state共有。
- Tetrisの固定60Hz frame logic。
- server側Zenoh再接続なし。
- prodの`AUTH_REQUIRED`既定false。
- RoomTokenがJWT `sub`に束縛されない。
- Formula NIFのbyte/instruction/gas上限とDirtyCpuなし。
- FormulaStore ETS所有者不定。
- client predictionがstub、補間が安定IDなし。
- WASM networkがstub。
- client testがCI対象外、property/fuzz/benchなし。
- telemetryがconsole/log中心。
- world-server release、multi-OS/installer、依存監査なし。

### 新規または今回初めて明確化

- **認証UIを追加したのにroom参加へ接続されていない**: `client/app`はAuthClientを構成するが、NetworkRenderBridgeは生protobufを送るため、secure modeのvertical sliceが成立しない。
- **binary64保証とf32 wire/render契約の矛盾**: visionの最上位保証をclient contractが満たさない。
- **physics評価対象の実装不在**: NIF縮小は理解できるが、現行visionが保証するphysics basisは代替実装を含めて見当たらない。
- **auth test suiteの縮小**: 現行auth-serverで確認できたExUnit test fileはrate limitとkeyの2本で、Accounts/Controller/token lifecycleの回帰網が著しく薄い。
- **superproject化後の保証文書崩壊**: `.workspace/0_docs/warranty/ci.md`がroot workflowとphysics crateを記載し、実際の4 workflowと一致しない。

## 直接的な評決

**総合 +26。優秀な部品を持つ研究開発基盤だが、現時点で「多数ユーザー向け分散3Dプラットフォーム」を保証できる製品ではない。**

SnapshotInterpolator、auth token lifecycle、JWKS verifier、Zenoh client recovery、wgpu rendererは明確に強い。一方、multi-room stateが共有され、secure modeで公式clientが入室できず、physics・binary64・Hub/editingというvisionの中核保証が実経路になっていない。Bevy/Godotの機能量と比べる以前に、まず「登録→認証→room参加→独立state→再接続→保存」の一本を閉じるべきである。

次の優先順位は、(1) room subtreeへScene Stackを移す、(2) auth `sub`付きRoomTokenをclientまで配線する、(3) client testをCIへ載せる、(4) prod認証をfail-secureにする、(5) physics/binary64保証を実装か文書のどちらかへ正直に揃える、である。
