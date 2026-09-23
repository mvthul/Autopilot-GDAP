fn main() {
    tauri_build::build();

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile("app.manifest.rc", embed_resource::NONE)
            .manifest_required()
            .expect("Windows application manifest could not be embedded");
    }
}
