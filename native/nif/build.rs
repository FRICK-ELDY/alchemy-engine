use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = PathBuf::from("../../proto");
    let proto_files = vec![proto_dir.join("frame_injection.proto")];

    for proto in &proto_files {
        println!("cargo:rerun-if-changed={}", proto.display());
    }

    println!("cargo:rerun-if-changed={}", proto_dir.display());
    prost_build::compile_protos(&proto_files, &[proto_dir])?;
    Ok(())
}
