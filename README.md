# AlchemyEngine

> A next-generation game engine fusing Elixir's robust state management with Rust's extreme performance.

AlchemyEngineは、ElixirをSingle Source of Truth（SSoT）としてゲームロジックとネットワークを統括し、RustのECS（Entity Component System）を用いてクライアント側の物理演算・描画・オーディオ処理を極限まで引き出す、ハイブリッドな次世代ゲームエンジンです。

## ✨ Core Concepts

- **Elixir as SSoT (Single Source of Truth)** 

  ゲームの権威ある状態（State）やロジックは、すべてElixir側で管理します。これにより、クライアント用のコードをそのままマルチプレイ用の専用サーバー（ヘッドレス化）としてシームレスに転用可能です。1000人規模のプレイヤーが交差するような大規模なネットワークルーティングも、Elixirの並行処理能力で安全に捌きます。

- **Data-Driven with Rust ECS** 

  Elixirから同期された状態をもとに、Rust側のECSが毎フレームの予測・補間（Dead Reckoning）と物理演算、描画を行います。機能ごとの固定スレッドではなく、タスクベースの並列処理を行うことで、広大なオープンワールドやVR環境でも高いフレームレートを死守します。

- **SuperCollider-inspired Audio Architecture** 

  クライアント（Elixir）が「指揮者」として非同期の制御メッセージを発行し、サーバー（Rust側の専用スレッド）がノードグラフを構築してDSP処理を行う、SuperColliderの思想を取り入れた強力な音響システムを搭載。複雑な空間オーディオ（3Dサウンド）や動的なルーティングを低遅延で実現します。

- **VR & Custom Hardware Ready** 

  Elixir側の柔軟なネットワークインターフェースにより、標準的なコントローラーだけでなく、自作のIoTデバイスからのUDPストリームを直接エンジンに吸い上げ、超低遅延でアバターに反映させる基盤を持ち合わせています。

## 🏗️ Architecture

プロジェクトは、ElixirのUmbrellaプロジェクトとRustのマルチクレート構成をシームレスに統合しています。

```text
alchemy-engine/
├── apps/                    # Elixir Umbrella Apps (Logic & Network)
│   ├── game_content/        # ゲームの静的データ・アセット管理
│   ├── game_engine/         # SSoTコアロジック・空間分割・ECSへの同期
│   ├── game_network/        # クライアント間・サーバー間通信
│   └── game_server/         # サーバー起動プロセス・ヘッドレス管理
└── native/                  # Rust Crates (Client Presentation & Processing)
    ├── game_core/           # ECS World・物理演算・予測補間 (ヘッドレス動作可能)
    ├── game_native/         # Elixir <-> Rust間のNIF通信インターフェース (Rustler)
    ├── game_render/         # WGPU/Vulkan等を用いた描画パイプライン
    └── game_window/         # ウィンドウ生成・OS入力イベント・オーディオスレッド
```

## 🚀 Getting Started

### Prerequisites
開発環境に以下のツールがインストールされている必要があります。
- [Elixir](https://elixir-lang.org/install.html) (OTP 25+)
- [Rust](https://www.rust-lang.org/tools/install) (cargo, rustc)

### Setup & Run
1. リポジトリをクローンします。
   ```bash
   git clone git@github.com:FRICK-ELDY/alchemy-engine.git
   cd alchemy-engine
   ```
2. Elixirの依存関係を取得し、Rustのネイティブコードをコンパイルします。
   ```bash
   mix deps.get
   mix compile
   ```
3. エンジンを起動します。
   ```bash
   iex -S mix
   ```

## 🤝 Contributing
（※チーム開発時のガイドラインや、コントリビューションルールの詳細をここに記載します）

## 📄 License
This project is licensed under the [MIT License](LICENSE).