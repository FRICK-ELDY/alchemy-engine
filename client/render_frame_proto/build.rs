fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = proto_resolve::resolve_proto_root()?;
    let fragments = [
        "render_frame.proto",
        "render_frame/cursor_grab.proto",
        "render_frame/mesh.proto",
        "render_frame/camera.proto",
        "render_frame/ui.proto",
        "render_frame/draw_commands.proto",
        "render_frame/audio_frame.proto",
    ];
    for rel in fragments {
        println!("cargo:rerun-if-changed={}", proto_root.join(rel).display());
    }
    println!("cargo:rerun-if-changed={}", proto_root.display());
    prost_build::compile_protos(&["render_frame.proto"], std::slice::from_ref(&proto_root))?;
    Ok(())
}
