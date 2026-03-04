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
- **Zero NIF Serialization Overhead**
  NIF 境界を通過するのは軽量な識別子のみ。バイナリのシリアライズコストをアーキテクチャレベルで排除しています。

## 🏗️ Architecture

プロジェクトは、ElixirのUmbrellaプロジェクトとRustのマルチクレート構成をシームレスに統合しています。

```text
alchemy-engine/
├── apps/                    # Elixir Umbrella Apps (Logic & Network)
│   ├── contents/            # ゲームの静的データ・アセット管理
│   ├── core/                # SSoTコアロジック・空間分割・ECSへの同期
│   ├── network/             # クライアント間・サーバー間通信
│   └── server/              # サーバー起動プロセス・ヘッドレス管理
└── native/                  # Rust Crates (スレッド・インターフェース単位)
    ├── physics/             # ECS World・ゲームロジック・物理演算・Dead Reckoning
    │                        #   (rustler 非依存 — ヘッドレス動作・ベンチマーク可能)
    ├── audio/               # SuperCollider風コマンド駆動オーディオスレッド
    │                        #   (専用スレッド + mpsc チャネル、Elixirが指揮者)
    ├── render/              # WGPU描画パイプライン + ウィンドウ管理・OS入力イベント
    │                        #   (wgpu 描画 + winit ウィンドウ管理)
    └── nif/                 # Elixir <-> Rust NIF通信インターフェース (Rustler)
                             #   (physics / audio / render を束ねる薄い層)
```

## 🚀 Getting Started

### Prerequisites

開発環境に以下のツールがインストールされている必要があります。

- [Elixir](https://elixir-lang.org/install.html) **1.19 / OTP 28**
- [Rust](https://www.rust-lang.org/tools/install) (stable)

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

---

## ✅ 品質保証

| 対象 | ツール | 保証内容 |
|:---|:---|:---|
| Rust コードスタイル | `cargo fmt` | フォーマット統一 |
| Rust 静的解析 | `cargo clippy -D warnings` | 警告ゼロ |
| Rust ユニットテスト | `cargo test` | 物理演算ロジックの正確性 |
| Rust パフォーマンス | `cargo bench`（main のみ） | 前回比 +10% 超の劣化をブロック |
| Elixir コードスタイル | `mix format` | フォーマット統一 |
| Elixir 静的解析 | `mix credo --strict` | コード品質・一貫性 |
| Elixir コンパイル | `mix compile --warnings-as-errors` | 警告ゼロ |
| Elixir 統合テスト | `mix test`（NIF ビルド込み） | Elixir/Rust 結合の動作保証 |

すべての push で GitHub Actions が自動実行されます。詳細は [docs/ci.md](./docs/ci.md) を参照。

---

## 🤝 Contributing

（※チーム開発時のガイドラインや、コントリビューションルールの詳細をここに記載します）

---

## Acknowledgments

### Vision Correction Pass（オプション機能）

VR/HMD 向けに、ソフトウェアによる視度補正（逆畳み込み Pre-filtering）を検討しています。本機能は **On/Off 切り替え可能** に設計します。詳細は [docs/paper/vision-correction-pass-tech-spec.md](./docs/paper/vision-correction-pass-tech-spec.md) を参照。

**参考研究**:
- Xu et al., "Software Based Visual Aberration Correction for HMDs," *IEEE VR*, 2018.
- Thibos et al., "Calculation of the geometrical point-spread function from wavefront aberrations," *Ophthalmic & Physiological Optics*, 2019.

### Patent Notice（特許に関する注意）

Vision Correction Pass で用いるアルゴリズム（逆畳み込み、処方箋からの PSF 導出、Wiener フィルタ等）は、第三者の特許の対象となる可能性があります。関連特許の例：US10529059B2（MIT/UCSD）、US20160314564A1（eSight）。本プロジェクトは特許の実施可能性（Freedom-to-Operate）を保証しません。利用前に適切な専門家にご相談ください。

---

## 📄 License

This project is licensed under either of

- [Apache License, Version 2.0](LICENSE-APACHE)
- [MIT License](LICENSE)

at your option.