fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());

    if let Ok(bindings) = cbindgen::generate(&crate_dir) {
        let out_dir = std::path::Path::new(&crate_dir)
            .parent()
            .unwrap_or(std::path::Path::new("."))
            .join("VitalsApp/Bridge/vitals.h");
        bindings.write_to_file(out_dir);
    }
}
