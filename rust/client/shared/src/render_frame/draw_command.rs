//! 1 フレーム分の描画命令。
//! Elixir（contents）が組み立て、`Content.FrameEncoder` で protobuf 化され、Zenoh の `game/.../frame` 等経由でクライアントの `render` が消費する。

use super::MeshVertex;

/// 1フレーム分の描画命令。
#[derive(Clone, Debug)]
pub enum DrawCommand {
    /// プレイヤースプライト描画。
    /// `render_bridge.rs` が補間後にこのバリアントの座標を書き換える。
    /// `Sprite` と分離することで、補間対象を型安全に特定できる。
    PlayerSprite { x: f32, y: f32, frame: u8 },
    /// パーティクル描画
    Particle {
        x: f32,
        y: f32,
        r: f32,
        g: f32,
        b: f32,
        alpha: f32,
        size: f32,
    },
    /// アイテム描画
    Item { x: f32, y: f32, kind: u8 },
    /// 障害物描画
    Obstacle {
        x: f32,
        y: f32,
        radius: f32,
        kind: u8,
    },
    /// 3D ボックス描画（R-5）
    Box3D {
        x: f32,
        y: f32,
        z: f32,
        half_w: f32,
        half_h: f32,
        half_d: f32,
        color: [f32; 4],
    },
    /// 3D 球（`MeshDef` 名 `unit_sphere`、半径 0.5 の単位球を `radius` でスケール）
    Sphere3D {
        x: f32,
        y: f32,
        z: f32,
        radius: f32,
        color: [f32; 4],
    },
    /// 3D 円錐（`MeshDef` 名 `unit_cone`。フィールド意味は `Box3D` と同じ half 拡張）
    Cone3D {
        x: f32,
        y: f32,
        z: f32,
        half_w: f32,
        half_h: f32,
        half_d: f32,
        color: [f32; 4],
    },
    /// グリッド地面描画（R-5）— パラメータから Rust が頂点を生成（後方互換）
    GridPlane {
        size: f32,
        divisions: u32,
        color: [f32; 4],
    },
    /// グリッド地面描画（P3）— Elixir が頂点を生成して渡す
    GridPlaneVerts { vertices: Vec<MeshVertex> },
    /// スカイボックス（単色グラデーション）描画（R-5）
    Skybox {
        top_color: [f32; 4],
        bottom_color: [f32; 4],
    },
    /// 汎用スプライト描画（UV・サイズをコンテンツ側が直接指定する）。
    /// `Sprite` の kind_id → UV/サイズ変換テーブルを持たない新コンテンツ向け。
    SpriteRaw {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        /// アトラス UV オフセット（0.0〜1.0）
        uv_offset: [f32; 2],
        /// アトラス UV サイズ（0.0〜1.0）
        uv_size: [f32; 2],
        /// RGBA 乗算カラー
        color_tint: [f32; 4],
    },
}
