// Verifies lossless JSON hook edits across mixed matchers and deletion boundaries.
// Exercises setup_json_edit and the production hook transformation together.
// Dependencies: serde_json, setup_hooks.

use super::update;
use crate::commands::setup_hooks::apply_hook_changes;
use serde_json::{Value, json};

const UNMANAGED: &str = r#"{ "type" : "command", "command" : "other-tool \"run\"", "x" : 1e2 }"#;

#[test]
fn setup_json_refresh_and_remove_preserve_unmanaged_bytes() {
    let raw = format!(
        r#"{{
  "theme" : "\u0064ark", "number": 2.00,
  "hooks": {{ "SessionStart" : [{{ "matcher" : "", "hooks": [
    {{"type":"command","command":"hiboss hook session-start","timeout": 1.00}},
    {UNMANAGED},
    {{"type":"command","command":"hiboss hook session-start"}}
  ]}}], "Notification" : [], "Stop": [{{"matcher":"", "hooks": []}}] }}
}}
"#
    );
    let mut settings: Value = serde_json::from_str(&raw).expect("settings");
    apply_hook_changes(&mut settings, false, None, "claude").expect("refresh");
    let refreshed = update(&raw, &settings).expect("targeted refresh");
    assert!(refreshed.contains(UNMANAGED));
    assert!(refreshed.contains(r#""theme" : "\u0064ark", "number": 2.00"#));
    assert!(refreshed.contains(r#""timeout": 1.00"#));
    assert_eq!(
        serde_json::from_str::<Value>(&refreshed).expect("JSON"),
        settings
    );
    apply_hook_changes(&mut settings, true, None, "claude").expect("remove");
    let removed = update(&refreshed, &settings).expect("targeted removal");
    assert!(removed.contains(UNMANAGED));
    assert!(removed.contains(r#""Notification" : []"#));
    assert!(removed.contains(r#""Stop": [{"matcher":"", "hooks": []}]"#));
    assert_eq!(
        serde_json::from_str::<Value>(&removed).expect("JSON"),
        settings
    );
}

#[test]
fn setup_json_add_remove_restores_original_settings_bytes() {
    for raw in [
        "{}\n",
        " { \n } \n",
        r#"{"theme": "\u0064ark", "number" : 1e2}"#,
        r#"{"hooks": {"SessionStart" : [{"matcher": "", "hooks": []}]}, "tail": true}"#,
    ] {
        let mut settings: Value = serde_json::from_str(raw).expect("settings");
        apply_hook_changes(&mut settings, false, None, "claude").expect("add");
        let added = update(raw, &settings).expect("insert");
        apply_hook_changes(&mut settings, true, None, "claude").expect("remove");
        assert_eq!(update(&added, &settings).expect("remove"), raw);
    }
}

#[test]
fn setup_json_deletes_adjacent_managed_matchers_without_reserializing_neighbors() {
    for matchers in [
        format!("{{\"hooks\":[{UNMANAGED}]}},{{\"hooks\":[{{\"command\":\"hiboss hook stop\"}}]}}"),
        format!("{{\"hooks\":[{{\"command\":\"hiboss hook stop\"}}]}},{{\"hooks\":[{UNMANAGED}]}}"),
    ] {
        let raw = format!("{{\"hooks\":{{\"Stop\":[{matchers}]}}}}");
        let mut settings: Value = serde_json::from_str(&raw).expect("settings");
        apply_hook_changes(&mut settings, true, None, "claude").expect("remove");
        let removed = update(&raw, &settings).expect("edit");
        assert!(removed.contains(UNMANAGED));
        assert_eq!(
            serde_json::from_str::<Value>(&removed).expect("JSON"),
            settings
        );
    }
}

#[test]
fn setup_json_rejects_duplicate_keys_and_malformed_input_without_writing() {
    assert!(update(r#"{"theme":1,"theme":2}"#, &json!({"theme":2})).is_err());
    assert!(update("{broken", &json!({})).is_err());
}
