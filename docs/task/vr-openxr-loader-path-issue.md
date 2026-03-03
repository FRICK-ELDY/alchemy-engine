# 課題: OpenXR ローダー（LoadLibraryExW failed）

> ステータス: 未解決（クローズ）  
> 作成日: 2026-03-03

## 現象

Steam を標準パス外（例: `D:\Environment\Steam`）にインストールしている環境で、VR 有効時に以下のエラーが出る:

```
[VR] OpenXR 初期化失敗: OpenXR loader failed: LoadLibraryExW failed
```

## 原因

- `openxr` crate の `Entry::load()` は `openxr_loader.dll` をプラットフォームのデフォルト探索（実行ファイルディレクトリ、PATH 等）で探す
- SteamVR の `openxr_loader.dll` は `{Steamのルート}\steamapps\common\SteamVR\bin\win64\` にあり、このパスがデフォルト探索に含まれない環境では見つからない

## 試した対応

| 対応 | 結果 |
|:---|:---|
| PATH に SteamVR の bin を追加して起動 | ユーザーが毎回設定する必要があり、許容しがたい |
| 独自環境変数 `OPENXR_LOADER_PATH` で `Entry::load_from(path)` を使用 | プロジェクト固有の設定になりすぎる（ユニークすぎる） |

## 望ましい解決（将来）

- ローダーをアプリに同梱する、または OpenXR 標準の仕組みでパス解決するなど、**ユーザー設定不要で動作する**方法を検討する
- 他プロジェクト・他ランタイムでの一般的な扱いを参考にする

## 参考

- `docs/task/vr-debug-logs.md` — デバッグログの見方（一時的な回避策として PATH の記載あり）
- Steam のインストール場所:  Steam クライアント「設定 → ストレージ」で確認可能
