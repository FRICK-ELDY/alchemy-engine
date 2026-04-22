use std::fs;
use std::path::{Path, PathBuf};

fn proto_root_dir() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let p = match std::env::var("PROTO_ROOT") {
        Ok(root) => PathBuf::from(root),
        Err(_) => Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../3rdparty/alchemy-protocol/proto"),
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


fn collect_proto_files(proto_dir: &Path) -> Result<Vec<PathBuf>, Box<dyn std::error::Error>> {
    let mut protos: Vec<PathBuf> = fs::read_dir(proto_dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().and_then(|ext| ext.to_str()) == Some("proto"))
        .map(|e| PathBuf::from(e.file_name()))
        .collect();
    protos.sort();
    if protos.is_empty() {
        return Err(format!("no .proto files under {}", proto_dir.display()).into());
    }
    Ok(protos)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = proto_root_dir()?;
    let proto_files = collect_proto_files(&proto_dir)?;

    for proto in &proto_files {
        println!("cargo:rerun-if-changed={}", proto_dir.join(proto).display());
    }

    println!("cargo:rerun-if-changed={}", proto_dir.display());
    prost_build::compile_protos(&proto_files, &[proto_dir])?;
    Ok(())
}
