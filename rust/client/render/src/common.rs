//! 共通のパイプライン・シェーダー(WGSL)管理
//!
//! 描画ロジックの共通部分。
//! platform/desktop は wgpu Surface 生成とデスクトップ固有の実装を担当。

/// シェーダーパス定数（platform/desktop の renderer が参照）
pub const SHADER_SPRITE: &str = "renderer/shaders/sprite.wgsl";
pub const SHADER_MESH: &str = "renderer/shaders/mesh.wgsl";
