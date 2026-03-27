use std::fs;
use std::path::{Path, PathBuf};

fn collect_proto_files(proto_dir: &Path) -> Result<Vec<PathBuf>, Box<dyn std::error::Error>> {
    let mut protos: Vec<PathBuf> = fs::read_dir(proto_dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|ext| ext.to_str()) == Some("proto"))
        .collect();
    protos.sort();
    if protos.is_empty() {
        return Err(format!("no .proto files under {}", proto_dir.display()).into());
    }
    Ok(protos)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = PathBuf::from("../../proto");
    let proto_files = collect_proto_files(&proto_dir)?;

    for proto in &proto_files {
        println!("cargo:rerun-if-changed={}", proto.display());
    }

    println!("cargo:rerun-if-changed={}", proto_dir.display());
    prost_build::compile_protos(&proto_files, &[proto_dir])?;
    Ok(())
}
