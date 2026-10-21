// group(0): MVP 行列 Uniform（メッシュ・グリッドパスで使用）
struct MvpUniform {
    mvp: mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> u_mvp: MvpUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color:    vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0)       color:         vec4<f32>,
};

// メッシュ・グリッド用: MVP 変換を適用する
@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = u_mvp.mvp * vec4<f32>(in.position, 1.0);
    out.color = in.color;
    return out;
}

// スカイボックス用: 頂点座標をクリップ空間として直接出力する。
// u_mvp の内容（3D カメラ行列）には依存しない。
@vertex
fn vs_sky(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = vec4<f32>(in.position, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
