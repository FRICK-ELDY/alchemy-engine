// group(0): テクスチャ・サンプラー
@group(0) @binding(0) var sprite_texture: texture_2d<f32>;
@group(0) @binding(1) var sprite_sampler: sampler;

// group(1): 画面サイズ Uniform
struct ScreenUniform {
    half_size: vec2<f32>, // (width / 2, height / 2)
};
@group(1) @binding(0) var<uniform> screen: ScreenUniform;

// group(2): カメラ Uniform（Step 20: プレイヤー追従スクロール）
struct CameraUniform {
    offset: vec2<f32>, // カメラのワールド座標オフセット（左上）
    _pad:   vec2<f32>,
};
@group(2) @binding(0) var<uniform> camera: CameraUniform;

struct VertexInput {
    @location(0) position: vec2<f32>,
};

// インスタンスごとのデータ（@location(1)〜(5)）
struct InstanceInput {
    @location(1) i_position:  vec2<f32>,
    @location(2) i_size:      vec2<f32>,
    @location(3) i_uv_offset: vec2<f32>,
    @location(4) i_uv_size:   vec2<f32>,
    @location(5) i_color_tint: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color_tint: vec4<f32>,
};

@vertex
fn vs_main(in: VertexInput, inst: InstanceInput) -> VertexOutput {
    var out: VertexOutput;

    // ワールド座標：インスタンスの左上 + 頂点オフセット（サイズ分）
    let world_pos = inst.i_position + in.position * inst.i_size;

    // カメラオフセットを引いてスクリーン座標に変換（Step 20）
    let screen_pos = world_pos - camera.offset;

    // クリップ座標（Y 軸は下が正なので反転）
    out.clip_position = vec4<f32>(
        (screen_pos.x - screen.half_size.x) / screen.half_size.x,
        -(screen_pos.y - screen.half_size.y) / screen.half_size.y,
        0.0,
        1.0,
    );

    // アトラス UV
    out.uv = inst.i_uv_offset + in.position * inst.i_uv_size;
    out.color_tint = inst.i_color_tint;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let tex_color = textureSample(sprite_texture, sprite_sampler, in.uv);
    return tex_color * in.color_tint;
}
