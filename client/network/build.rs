use std::fs;
use std::path::{Path, PathBuf};

fn collect_proto_rel_paths(proto_dir: &Path) -> Result<Vec<PathBuf>, Box<dyn std::error::Error>> {
    let mut protos = Vec::new();
    collect_proto_rel_paths_walk(proto_dir, proto_dir, &mut protos)?;
    protos.sort();
    if protos.is_empty() {
        return Err(format!("no .proto files under {}", proto_dir.display()).into());
    }
    Ok(protos)
}

fn rel_path_posix(rel: &Path) -> String {
    rel.components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

fn collect_proto_rel_paths_walk(
    base: &Path,
    dir: &Path,
    out: &mut Vec<PathBuf>,
) -> Result<(), Box<dyn std::error::Error>> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_proto_rel_paths_walk(base, &path, out)?;
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("proto") {
            out.push(path.strip_prefix(base)?.to_path_buf());
        }
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = proto_resolve::resolve_proto_root()?;
    let proto_files = collect_proto_rel_paths(&proto_dir)?;

    for proto in &proto_files {
        println!("cargo:rerun-if-changed={}", proto_dir.join(proto).display());
    }
    println!("cargo:rerun-if-changed={}", proto_dir.display());

    let compile_inputs: Vec<String> = proto_files.iter().map(|p| rel_path_posix(p)).collect();
    prost_build::compile_protos(
        &compile_inputs
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>(),
        &[proto_dir.as_path()],
    )?;
    Ok(())
}
