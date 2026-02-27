# アセット管理

## フォルダ構成（提案 A）

```
assets/
├── _shared/            共通スクリプト（gen_atlas.py, gen_audio.py）
├── sprites/            スプライト生成スクリプト・出力（従来）
├── audio/              音声生成スクリプト・出力（従来）
├── vampire_survivor/   ゲーム別アセット
│   ├── sprites/
│   └── audio/
├── mini_shooter/
│   ├── sprites/
│   └── audio/
└── README.md          本ファイル
```

## ゲーム別アセット生成

`GAME_ASSETS_ID` により `assets/{game_id}/` を参照します。

### ヴァンパイアサバイバー

```bash
python assets/_shared/gen_atlas.py assets/vampire_survivor/sprites
python assets/_shared/gen_audio.py assets/vampire_survivor/audio
```

### ミニシューター

```bash
python assets/_shared/gen_atlas.py assets/mini_shooter/sprites
python assets/_shared/gen_audio.py assets/mini_shooter/audio
```

## 従来の出力先（後方互換）

引数なしで実行すると、`assets/sprites/` および `assets/audio/` に出力されます。
