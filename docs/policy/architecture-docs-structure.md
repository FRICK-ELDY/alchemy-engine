# ポリシー: アーキテクチャドキュメントの構成

> 作成日: 2026-03-08  
> ステータス: 採用

---

## 1. 方針

- **全体構成**: Elixir / Rust ではなく、**サーバー / クライアント**で分割して記述する
- **Rust ドキュメント**: クレート構成に合わせて配置する

---

## 2. ディレクトリ構成

```
docs/architecture/
├── overview.md              # 全体の流れ（サーバー/クライアント分割）
├── rust/
│   ├── nif.md              # NIF 全体
│   ├── nif/                # サーバー内 Rust
│   │   ├── physics.md
│   │   └── audio.md
│   ├── client_desktop.md   # クライアント exe
│   ├── desktop/            # クライアント側
│   │   ├── input.md
│   │   ├── input_openxr.md
│   │   └── render.md
│   └── launcher.md
└── elixir/                 # 従来どおり
```

---

## 3. 統合ルール

- `rust/render.md` → `rust/desktop/render.md`
- `rust/input_openxr.md` → `rust/desktop/input_openxr.md`
- `rust/physics.md` → `rust/nif/physics.md`
- `rust/audio.md` → `rust/nif/audio.md`
- 重複するドキュメントは統合し、参照リンクを更新する
