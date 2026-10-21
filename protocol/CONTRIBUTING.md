# Contributing（`.proto` 変更）

## レビュー

- **`proto/**` の変更**は、組織のポリシーに従い **メンテナの承認**を得てください（外部コントリビュータ向けには branch protection / CODEOWNERS の利用を推奨）。
- 可能であれば **Elixir と Rust の両方**に関わるメンバーが目を通すようにします。

## フィールド番号と互換性

- **proto3** では、既存フィールドの **番号の再利用禁止**。不要になったフィールドは `reserved` で明示してください。
- **同一 MAJOR** では原則として **フィールド追加のみ**を後方互換変更とみなします。意味の変更・型の変更は破壊的になり得るため、`CHANGELOG.md` に記載し **`MAJOR` バンプ**を検討してください。

## 参考

- エンジン側の分離手順の全体像: alchemy-engine の `workspace/2_todo/protocol-repo-extraction-procedure.md`（該当リポジトリ内）。
