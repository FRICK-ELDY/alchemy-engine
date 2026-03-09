## 1.ディレクトリ構成 (`native/`)
設計思想
- Elixir (The Brain): 真実の状態（State）を管理し、論理的な判断を下す。
- Rust (The Body): 通信（Zenoh）、計算（NIF/shared）、描画（wgpu）を担当し、高パフォーマンスに実行する。
- Shared Memory Layout: #[repr(C)] によるゼロコピー通信で、Elixir-Rust間の壁を破壊する。

Workspace機能を利用し、役割ごとにクレート（フォルダ）を分離します。
```
bin/
├── build.bat                 # デバック・リリースビルド用スクリプト
├── launcher.bat              # 開発用のランチャー起動
native/
├── Cargo.toml                # Workspace全体の管理
│
├── shared/                   # 【共通データ】Elixirとの契約、予測、補間
│   ├── src/
│   │   ├── lib.rs            # 全体の統合（World State）
│   │   ├── types.rs          # #[repr(C)] 構造体（Elixirとの共通規格）
│   │   ├── store.rs          # スナップショット保持（過去と現在）
│   │   ├── interp.rs         # 線形補間(Lerp)ロジック（20Hz -> 60Hz）
│   │   └── predict.rs        # 入力予測ロジック（レイテンシ対策）
│
├── network/                  # 【通信層】Zenohによる高速トランスポート
│   ├── src/
│   │   ├── lib.rs            # 通信インターフェース
│   │   ├── common.rs         # トピック管理、共通処理
│   │   └── platform/         # 通信方式の切り替え
│   │       ├── mod.rs        # target_os による振り分け
│   │       ├── desktop.rs    # Zenoh Native (UDP/TCP)
│   │       └── web.rs        # Zenoh over WebSocket (WASM)
│
├── audio/                    # 【聴覚層】音の再生とマイク入力
│   ├── src/
│   │   ├── lib.rs            # オーディオミキサー、エンジンの初期化
│   │   ├── common.rs         # DSP（エフェクト）、立体音響（Spatial Audio）計算
│   │   └── platform/         # OSごとの音声ドライバ (cpal / rodio 等)
│   │       ├── mod.rs        # target_os による切り替え
│   │       ├── desktop.rs    # CoreAudio / WASAPI / ALSA
│   │       ├── web.rs        # Web Audio API (WASM)
│   │       ├── android.rs    # Oboe / AAudio
│   │       └── ios.rs        # AudioUnit
│
├── render/                   # 【描画層】wgpuを用いた共通レンダラー
│   ├── src/
│   │   ├── lib.rs            # 外向きのレンダラーAPI
│   │   ├── common.rs         # 共通のパイプライン、シェーダー(WGSL)管理
│   │   └── platform/         # OSごとのSurface生成
│   │       ├── mod.rs        # target_os による切り替え
│   │       ├── desktop.rs    # Win / Mac / Linux
│   │       ├── web.rs        # WASM (Canvas)
│   │       ├── android.rs    # Vulkan / Surface
│   │       └── ios.rs        # Metal / Layer
│
├── window/                   # 【窓層】winitを用いたイベント管理
│   ├── src/
│   │   ├── lib.rs            # ライフサイクル管理（AppHandler）
│   │   ├── common.rs         # 入力イベントの正規化
│   │   └── platform/         # OS固有処理（Suspend/Resume等）
│
├── xr/                       # 【XR層】OpenXRセッションと入力管理
│   ├── src/
│   │   ├── lib.rs            # セッション初期化、フレームループ管理
│   │   ├── common.rs         # アクションマッピング（トリガー、スティック等の正規化）
│   │   └── platform/         # ランタイム固有の初期化
│   │       ├── mod.rs
│   │       ├── desktop.rs    # PCVR (SteamVR, Oculus, Monado)
│   │       └── android.rs    # Meta Quest 等の一体型 (OpenXR Mobile)
│
├── app/                      # 【統合層】各ターゲットのエントリポイント
│   ├── src/
│   │   ├── main.rs           # Desktop用 (exe/app)
│   │   ├── lib.rs            # WASM / Mobile用
│   │   ├── android.rs        # Android JNI
│   │   └── ios.rs            # iOS Swiftブリッジ
│
├── nif/                      # 【サーバー】Elixir NIF用 Rustコード
│   ├── src/
│   │   ├── lib.rs            # Rustlerによる関数露出（sharedを参照）
│   │   ├── physics.rs        # 剛体物理等の演算
│   │   ├── ai.rs             # contents制作用のAIアシスタント
│   │   └── audio_sync.rs     # オーケストラなどの音同期
│
└── tools/                    # 【開発支援】プロダクトには含まれないツール
    └── launcher/             # ルーター、サーバー、クライアントの一括起動ツール
        ├── src/main.rs
```

## 2. 各レイヤーの責務と設計指針

### shared (The Mirror - 鏡)
Elixirの状態をRust側に「映し出す」ための層。
- Zero-Copy: `bytemuck` クレートを使用。受信したバイナリをパースせず、そのまま構造体にキャスト（覗き見）して爆速化します。
- Smoothing: サーバーの低頻度な更新（20Hz）を、描画のタイミングに合わせて滑らかに補間します。

### network (The Pipe - 導管)
外部とデータをやり取りする層。
- Agnostic: 上位レイヤー（shared等）には「UDPかWebSocketか」を意識させず、「データが届いた」という事実だけを伝えます。

### render (The Eye - 瞳)
wgpuを採用。プラットフォームを問わず同一の描画結果を保証します。
- Instancing: Elixirから届く大量のオブジェクト群をGPUインスタンシングで一括描画し、ドローコールを最小化します。

### window (The Shell - 殻)
winitを用いてOSの窓やライフサイクルを管理します。
- Normalization: OSごとにバラバラなマウス座標やDPIスケールを、エンジン共通の数値に変換します。

## 3. データ同期の仕組み
- Elixir (Server): 真実の状態を計算。バイナリを構築しZenohで送信。
- network (Client): バイナリを受信し、shared の store へ保存。
- shared (Client): 現在時刻に基づき、過去と最新のスナップショットから「中間の座標」を計算。
- render (Client): 計算された座標をGPUに送り、描画。
- window (Client): ユーザーの操作を拾い、network 経由でElixirへフィードバック。

## 4. 今後の実装指針
Shared types first: 変更があるときは必ず shared/types.rs から修正し、サーバーとクライアントの契約を更新する。

Zero-copy focus: パース（解析）コードを書かず、バイナリを直接覗き込む設計を維持する。

Platform isolation: OS固有のAPIが必要になったら迷わず platform/ 以下にファイルを分ける。

launcherに
プロファイル起動: 「デバッグ描画ありモード」「ネットワーク遅延シミュレーションモード」などを引数で切り替えてクライアントを叩く。
このLauncherに「Elixirサーバーのホットリロード監視」や「WASMビルドの自動実行」などの機能を追加する


オーディオ同期のデータフロー（ボイスチャット含む）
ボイスチャットを実現する場合、データの流れは以下のようになります。

- Shared (定義): shared/src/types.rs に、音声パケット（Opusなどの圧縮形式）と再生指示（「どの位置からどの音を出すか」）のデータ構造を定義します。
- NIF (同期/リレー): * 各クライアントからの音声ストリームを受け取り、誰が誰の近くにいるかに基づいて「誰にどの音声を届けるか」を判断します。
- オーディオの「再生タイミング（Presentation Time Stamps）」を管理し、全ユーザーが同じタイミングで音を聞けるように同期信号を生成します。
- Network (運搬): Zenohの高速なPub/Sub（特にUDPベースのトランスポート）を利用して、音声バイナリをやり取りします。
- Audio (出力): shared の定義と network からのストリームを受け取り、common.rs でミキシングや立体音響処理（距離減衰など）を行ってから platform/ 経由でスピーカーから鳴らします。

VR入力のデータフロー (OpenXR → Elixir)
VRの入力（手の位置、ボタン）をサーバーに送る際、これまでの shared と network を以下のように活用します。
- shared/types.rs: VrInput や VrPose（手の座標や回転）などの型を定義します。
- xr/common.rs: OpenXRから届く生のデータを shared::types の形式に変換します。
- network: 変換された VrInput を Zenoh で Elixir サーバーへ爆速で飛ばします。
- Elixir: 受け取った手の位置を元に、物理判定（物を掴むなど）を行い、結果を全クライアントへ返します。

レンダリング層 (render) への影響
VRでは「右目用」と「左目用」の2枚の絵を描く必要があります。ここが wgpu との連携の鍵です。
wgpuのSurface: 通常はウィンドウに描画しますが、VRでは OpenXRが提供するテクスチャ（Swapchain） に対して描画します。
render/platform/desktop.rs: ここに「OpenXRのテクスチャをwgpuのターゲットとして認識させる」ロジックを配置します。
