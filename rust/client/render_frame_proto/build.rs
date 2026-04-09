fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = "../../../proto";
    let entry = format!("{}/render_frame.proto", proto_root);
    let fragments = [
        "render_frame.proto",
        "render_frame/cursor_grab.proto",
        "render_frame/mesh.proto",
        "render_frame/camera.proto",
        "render_frame/ui.proto",
        "render_frame/draw_commands.proto",
    ];
    for rel in fragments {
        println!("cargo:rerun-if-changed={}/{}", proto_root, rel);
    }
    prost_build::compile_protos(&[entry.as_str()], &[proto_root])?;
    Ok(())
}
