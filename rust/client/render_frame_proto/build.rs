fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto = "../../../proto/render_frame.proto";
    println!("cargo:rerun-if-changed={}", proto);
    prost_build::compile_protos(&[proto], &["../../../proto"])?;
    Ok(())
}
