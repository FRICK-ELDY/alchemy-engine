use std::path::{Path, PathBuf};

fn proto_root_dir() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let p = match std::env::var("PROTO_ROOT") {
        Ok(root) => PathBuf::from(root),
        Err(_) => {
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../3rdparty/alchemy-protocol/proto")
        }
    };
    if !p.is_dir() {
        return Err(format!(
            "PROTO_ROOT proto directory missing: {} (init submodule: git submodule update --init --recursive)",
            p.display()
        )
        .into());
    }
    Ok(p)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = proto_root_dir()?;
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
