## 1.ディレクトリ構成 (`rust/`)
設計思想
- Elixir (The Brain): 真実の状態（State）を管理し、論理的な判断を下す。
- Rust (The Body): 通信（Zenoh）、計算（NIF/shared）、描画（wgpu）を担当し、高パフォーマンスに実行する。
- Shared Memory Layout: #[repr(C)] によるゼロコピー通信で、Elixir-Rust間の壁を破壊する。

Workspace機能を利用し、役割ごとにクレート（フォルダ）を分離します。
```
rust/
├── Cargo.toml                # Workspace 全体の管理（members: nif, launcher, client/*）
│
├── nif/                      # 【サーバー】Elixir NIF（現行は Formula VM のみ）
│   └── src/ …
│
├── launcher/                 # ルーター・サーバ・クライアント起動（開発支援）
│   └── src/main.rs
│
└── client/
    ├── shared/               # 【共通データ】Elixirとの契約、予測、補間
    │   ├── src/
    │   │   ├── lib.rs            # 全体の統合（World State）
    │   │   ├── types.rs          # #[repr(C)] 構造体（Elixirとの共通規格）
    │   │   ├── store.rs          # スナップショット保持（過去と現在）
    │   │   ├── interp.rs         # 線形補間(Lerp)ロジック（20Hz -> 60Hz）
    │   │   └── predict.rs        # 入力予測ロジック（レイテンシ対策）
    │
    ├── network/              # 【通信層】Zenoh 等
    ├── audio/                # 【聴覚層】
    ├── render_frame_proto/   # RenderFrame protobuf デコード
    ├── render/               # 【描画層】wgpu
    ├── window/               # 【窓層】winit
    ├── xr/                   # 【XR層】OpenXR
    └── app/                  # 【統合層】VRAlchemy 等（各クレートは src/ 以下に詳細）
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
