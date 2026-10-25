//! The embedded default_config.json stays in step with harper-core's curated
//! set: it is the same file, copied from harper-core v1.2.2. If the Harper pin
//! moves and the file changes shape, this test says so.

use harper_core::linting::{HumanReadableStructuredConfig, StructuredConfig};

#[test]
fn the_embedded_config_matches_harpers_curated_config() {
    let embedded: HumanReadableStructuredConfig = serde_json::from_str(include_str!(
        "../src/default_config.json"
    ))
    .expect("default_config.json parses as Harper's human-readable config");
    assert_eq!(
        embedded.to_structured_config(),
        StructuredConfig::curated().into(),
        "src/default_config.json drifted from harper-core's curated config"
    );
}
