このドキュメントは、コンテンツを最小単位まで分解し、VR空間で直感的な論理構築を可能にするための究極の地図です。

# Blueprint

## 1. 存在の階層構造（The Four Pillars）

すべてのデジタル体験は、以下の4層の連鎖（パイプライン）で構成されます。

- Contents（体験）: ユーザーが知覚する最終的な物語や空間。
- Components（役割）: ノードを束ねて特定の「機能」を持たせた細胞。
- Nodes（論理）: ActionとLogicが交差する処理の原子。
- Types（定義）: 世界に存在する物質そのものの定義。

## 2. 二つの血流（Action & Logic Lines）

ノードプログラミングを「時間の制御」と「データの参照」に分離し、それらを自由に組み合わせます。

- Action Line（実行フロー）:
  > 役割: 「いつ（When）」を司る。パルス（信号）による実行権限の委譲。
  > 機能: 順次処理、並列処理、および複数の時間を束ねる Sync（同期）。
  > 端子: {in, out}。
- Logic Line（データフロー）:
  > 役割: 「何を（What）」を司る。情報の参照と変換。
  > 機能: 常に流れるストリーム、または要求に応じた値（Value）の返却。
  > 端子: {in, out}。

## 3. 統一ディレクトリ・アーキテクチャ（Symmetrical Structure）
Components と Nodes は、全く同じ構造的DNAを持ち、高い予測可能性を維持します。

■ Components 層
```
lib/contents/components/
├ core/behavior.ex: 全コンポーネント共通のライフサイクル規約。
├ category/: 目的別の分類。
│ ├ uncategorized/comment.ex: VR空間内のドキュメント化（付箋）。
```
■ Nodes 層
```
lib/contents/components/nodes/
├ core/behavior.ex: ノードとしてのインターフェース定義（Action/Logicの宣言）。
├ lines/: 通信のルール（action.ex, logic.ex）。
├ category/: ドメイン別の機能群。
│ ├ state/write.ex: 実行と情報のハイブリッドノード。
│ ├ math/add.ex: 純粋なロジック演算。

```
■ Types 層
```
ノードが扱う「定義」
lib/contents/components/types/
├ category/users/local_user.ex: 操作者というコンテキスト。
├ category/object/string.ex: 文字列の実体。
├ category/data/int.ex: 数値の原子。
```

## 4. 設計のゴール：能動と受動の融合
ノードを「Action型」か「Logic型」かで分けるのではなく、**「どのような能力（Line）を備えているか」**で定義します。
> 例：write.ex ノードの解釈
> 「Action Line からパルスを受け取った瞬間に動き出し、Logic Line からデータを吸い上げ（Sample）、対象を書き換える。終われば Action Line へパルスを返す。」

## 5. VR体験における開発指針
- 直感的な線: Action（時間）は「光る脈動」として、Logic（情報）は「静かな導管」として視覚化する。
- 対称性の保持: 階層が違っても、インターフェースが同じであれば、ユーザーは一度覚えたルールでシステム全体を構築できる。
- 型の厳格さ: types がカテゴリー化されていることで、VR空間で「今、何を触っているのか」を型レベルでユーザーが意識できるようにする。

この構造は、単なるコードの整理術ではなく、AlchemyEngineという「世界を構築するための言語」そのものです。この地図があれば、どれほど複雑なコンテンツであっても迷うことなく最小単位に分解し、再構築できるはずです。