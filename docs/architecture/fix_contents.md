このドキュメントは、コンテンツを最小単位まで分解し、VR空間で直感的な論理構築を可能にするための究極の地図です。

# Blueprint

## 1. 存在の階層構造（The Four Pillars）

すべてのデジタル体験は、以下の層の連鎖（パイプライン）で構成されます。

- **Contents（体験）**: ユーザーが知覚する最終的な物語や空間。既存の `lib/contents/` 配下に配置。
- **Objects（空間のピア）**: 空間に存在する実体（Entities）。GenServer として動作。
- **Components（状態のピア）**: ノードを束ねて特定の「機能」を持たせた細胞。状態を保持する。GenServer として動作。
- **Nodes（論理のピア）**: Action と Logic が交差する処理の原子。Logic Processors。GenServer として動作。
- **Schemas（設計図）**: 世界に存在する物質そのものの定義。ノード・コンポーネントが扱うデータの型。

## 2. 依存関係（Dependency Direction）

下位層への一方向依存を維持します。

```
objects |> schemas
objects |> components |> schemas
objects |> nodes |> schemas
objects |> components |> nodes |> schemas
```

## 3. 二つの血流（Action & Logic Lines）

ノードプログラミングを「時間の制御」と「データの参照」に分離し、それらを自由に組み合わせます。

- **Action Line（実行フロー）**:
  - 役割: 「いつ（When）」を司る。パルス（信号）による実行権限の委譲。
  - 機能: 順次処理、並列処理、および複数の時間を束ねる Sync（同期）。
  - 端子: `{in, out}`。
- **Logic Line（データフロー）**:
  - 役割: 「何を（What）」を司る。情報の参照と変換。
  - 機能: 常に流れるストリーム、または要求に応じた値（Value）の返却。
  - 端子: `{in, out}`。

## 4. 統一ディレクトリ・アーキテクチャ（apps/contents）

```
apps/contents/
├── core/
│   └── behaviour.ex         # 憲法。全層共通の契約。（役割分担は別途詰める）
├── lines/                   # 通信のルール。Action / Logic のインターフェース。
│   ├── action.ex            # {in, out}
│   └── logic.ex             # {in, out}
├── schemas/                 # 設計図。ノード・コンポーネントが扱うデータの型定義。
│   └── category/
│       ├── data/            # プリミティブな値の定義
│       │   ├── string.ex
│       │   ├── boolean.ex
│       │   └── int.ex
│       ├── spatial/         # 空間に関わる型（Resonite に合わせた配置）
│       │   ├── transform.ex # 変換行列・位置・回転・スケール
│       │   └── vector3.ex   # 3次元ベクトル
│       └── users/
│           └── local_user.ex  # 操作者というコンテキスト
├── objects/                 # 空間のピア（Entities）
│   └── core/
│       └── behaviour.ex     # Object としてのインターフェース（GenServer 規約）
├── components/              # 状態のピア（State Holders）。GenServer で動作。
│   ├── core/
│   │   └── behaviour.ex     # 全コンポーネント共通のライフサイクル規約（GenServer 規約）
│   └── category/
│       └── uncategorized/
│           └── comment.ex   # VR 空間内のドキュメント化（付箋）
├── nodes/                   # 論理のピア（Logic Processors）
│   ├── core/
│   │   └── behaviour.ex     # ノードとしてのインターフェース（Action/Logic の宣言）
│   └── category/
│       ├── actions/         # 実行・副作用に軸を置くノード（Resonite に合わせた分類）
│       │   └── write.ex     # Action Line でトリガー、Logic Line でデータを書き換え
│       └── math/            # 純粋なロジック演算
│           └── add.ex
└── lib/contents/            # 既存 Contents（体験）。従来通り配置
    ├── vampire_survivor/
    ├── rolling_ball/
    ├── vr_test/
    └── ...
```

### 構成のコメント

| パス | 役割 |
|------|------|
| `core/behaviour.ex` | 憲法。全層が従う基本契約。`core/` と各層の `behaviour.ex` の役割分担は別途詰める。 |
| `lines/` | Action / Logic の端子 `{in, out}` を定義。システム全体で共有される通信のルール。 |
| `schemas/` | 設計図。データの形を定義。`category` でドメイン別に分類し、VR 空間での型の可視性を高める。 |
| `schemas/category/spatial/` | 空間に関わる型。Resonite の Components に合わせた配置。transform, vector3 など。 |
| `objects/` | 空間上の実体。ECS の Entity 相当。GenServer で動作。 |
| `components/` | 状態を保持する細胞。ノードを束ねて特定の機能を提供。GenServer で動作。 |
| `nodes/` | 論理の原子。Action / Logic Lines に基づく処理。GenServer で動作。`category/actions/` は Resonite の Actions に合わせた分類。 |

### プロセスモデル（GenServer）

Objects / Components / Nodes の 3 層は、当面すべて GenServer として実装する。一貫したモデルで実装を進め、負荷を計測したうえで、必要に応じて軽量な方式へ切り替える。

## 5. 設計のゴール：能動と受動の融合

ノードを「Action 型」か「Logic 型」かで分けるのではなく、**「どのような能力（Line）を備えているか」**で定義します。

> 例：write.ex ノードの解釈  
> 「Action Line からパルスを受け取った瞬間に動き出し、Logic Line からデータを吸い上げ（Sample）、対象を書き換える。終われば Action Line へパルスを返す。」

## 6. VR 体験における開発指針

- **直感的な線**: Action（時間）は「光る脈動」として、Logic（情報）は「静かな導管」として視覚化する。
- **対称性の保持**: 階層が違っても、インターフェースが同じであれば、ユーザーは一度覚えたルールでシステム全体を構築できる。
- **型の厳格さ**: schemas がカテゴリー化されていることで、VR 空間で「今、何を触っているのか」を型レベルでユーザーが意識できるようにする。

---

この構造は、単なるコードの整理術ではなく、AlchemyEngine という「世界を構築するための言語」そのものです。この地図があれば、どれほど複雑なコンテンツであっても迷うことなく最小単位に分解し、再構築できるはずです。
