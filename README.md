# AlchemyEngine

> A platform for worlds. You bring the rules.

3D空間とそこに存在するユーザーを保証するゲームエンジンです。

詳細は [ビジョンと設計思想](./docs/vision.md) を参照。

## アーキテクチャのハイライト

- **Elixir as SSoT**

  ゲームの権威ある状態とロジックはすべて Elixir 側で管理します。クライアント用のコードをそのままヘッドレスのマルチプレイサーバーとして転用可能です。1000人規模のプレイヤーが交差する大規模ネットワークも Elixir の並行処理能力で捌きます。
- **Rust ECS for Physics & Rendering**

  Elixir から同期された状態をもとに、Rust の ECS が 60Hz 固定の物理演算・描画・オーディオ処理を行います。SoA（Structure of Arrays）と SIMD による CPU キャッシュ最適化で、広大なオープンワールドでも高フレームレートを維持します。
- **SuperCollider-inspired Audio**

  Elixir が「指揮者」として非同期コマンドを発行し、Rust の専用スレッドが DSP 処理を行います。複雑な空間オーディオと動的ルーティングを低遅延で実現します。

## 🏗️ Architecture

プロジェクトは、ElixirのUmbrellaプロジェクトとRustのマルチクレート構成をシームレスに統合しています。

```text
alchemy-engine/
├── apps/                    # Elixir Umbrella Apps (Logic & Network)
│   ├── game_content/        # ゲームの静的データ・アセット管理
│   ├── game_engine/         # SSoTコアロジック・空間分割・ECSへの同期
│   ├── game_network/        # クライアント間・サーバー間通信
│   └── game_server/         # サーバー起動プロセス・ヘッドレス管理
└── native/                  # Rust Crates (スレッド・インターフェース単位)
    ├── game_simulation/     # ECS World・ゲームロジック・物理演算・Dead Reckoning
    │                        #   (rustler 非依存 — ヘッドレス動作・ベンチマーク可能)
    ├── game_audio/          # SuperCollider風コマンド駆動オーディオスレッド
    │                        #   (専用スレッド + mpsc チャネル、Elixirが指揮者)
    ├── game_render/         # WGPU描画パイプライン + ウィンドウ管理・OS入力イベント
    │                        #   (旧 game_render + game_window を統合)
    └── game_nif/            # Elixir <-> Rust NIF通信インターフェース (Rustler)
                             #   (game_simulation / game_audio / game_render を束ねる薄い層)
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