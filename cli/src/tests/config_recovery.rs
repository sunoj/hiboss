// Unit tests for config parsing and the recovery step each missing value points to.
// Covers empty, malformed and partial configs; errors must never echo stored values.
// Dependencies: crate::config.

use crate::config::{Config, parse_config};
use std::path::Path;

fn config(server: Option<&str>, key: Option<&str>) -> Config {
    Config {
        server: server.map(str::to_string),
        key: key.map(str::to_string),
        channel: None,
    }
}

#[test]
fn parse_config_treats_blank_body_as_default() {
    let parsed = parse_config("  \n", Path::new("/tmp/c.json")).expect("blank parses");
    assert!(parsed.server.is_none() && parsed.key.is_none());
}

#[test]
fn parse_config_reports_path_position_and_recovery_without_values() {
    let body = r#"{"key": "synthetic-secret", "server": 5}"#;
    let err = parse_config(body, Path::new("/tmp/c.json"))
        .expect_err("malformed")
        .to_string();
    assert!(
        err.contains("config file /tmp/c.json is not valid"),
        "{err}"
    );
    assert!(err.contains("line 1, column"), "{err}");
    assert!(err.contains("move the file aside as a backup"), "{err}");
    assert!(!err.contains("synthetic-secret"), "{err}");
}

#[test]
fn parse_config_reads_valid_body() {
    let parsed = parse_config(r#"{"server":"https://a"}"#, Path::new("c.json")).expect("valid");
    assert_eq!(parsed.server.as_deref(), Some("https://a"));
}

#[test]
fn require_server_points_fresh_install_to_init() {
    let err = config(None, None)
        .require_server()
        .expect_err("missing")
        .to_string();
    assert!(
        err.contains("not configured") && err.contains("hiboss init <server-url>"),
        "{err}"
    );
}

#[test]
fn require_server_with_key_points_to_config_set() {
    let err = config(Some("  "), Some("k"))
        .require_server()
        .expect_err("blank")
        .to_string();
    assert!(err.contains("hiboss config set server <url>"), "{err}");
}

#[test]
fn require_key_names_the_configured_server() {
    let err = config(Some("https://a"), Some(""))
        .require_key()
        .expect_err("blank")
        .to_string();
    assert!(
        err.contains("API key is missing") && err.contains("hiboss init <server-url>"),
        "{err}"
    );
    let err = config(None, None)
        .require_key()
        .expect_err("missing")
        .to_string();
    assert!(err.contains("hiboss init <server-url>"), "{err}");
}
