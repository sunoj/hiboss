// Purpose: Exercise live-state validation and help through the real CLI on a remote build box.
// Exports: CLI regression tests for static publication rejection and shipped examples.
// Dependencies: cli_ux_support's isolated sandbox, std and serde_json; no live server.

mod cli_ux_support;

use cli_ux_support::Sandbox;
use serde_json::{Value, json};
use std::{fs, path::PathBuf};

fn write_publication(workspace: &Sandbox, mut value: Value) -> PathBuf {
    value["taskKey"] = json!("guardrail-test");
    value["sessionId"] = json!("guardrail-session");
    let path = workspace.home.join("publication.json");
    fs::write(&path, serde_json::to_vec(&value).expect("publication JSON")).expect("write publication");
    path
}

fn cleanup(workspace: Sandbox) {
    let path = workspace.home.clone();
    assert!(path.is_dir(), "workspace removed unexpectedly");
    drop(workspace);
    assert!(!path.exists(), "remove isolated workspace");
}

#[test]
fn validate_and_publish_reject_static_reports_before_network_access() {
    let workspace = Sandbox::new();
    workspace.write_config(r#"{"server":"http://127.0.0.1:1","key":"test-only"}"#);
    let value = json!({
        "protocolVersion": 2, "catalogId": "hiboss.panel", "catalogVersion": 1,
        "title": "Execution finished",
        "spec": {"root": "text", "elements": {
            "text": {"type": "Text", "props": {"text": "All tests passed"}, "children": []}
        }},
        "stateSchema": {"type": "object", "properties": {"task": {"type": "object"}}},
        "initialState": {"task": {}}
    });
    let path = write_publication(&workspace, value);
    for command in ["validate", "publish"] {
        let output = workspace.run(&["panel", command, path.to_str().expect("UTF-8 path")]);
        assert_ne!(output.code, 0, "{command} accepted static content");
        assert_eq!(output.stderr.trim(),
            "Error: invalid_spec at /spec/elements: no live state is bound; a card with only static content is a message — use hiboss send");
    }
    cleanup(workspace);
}

#[test]
fn panel_validate_accepts_every_example_with_publication_identity() {
    let workspace = Sandbox::new();
    let examples = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../panel-runtime/fixtures/examples");
    let mut count = 0;
    for entry in fs::read_dir(examples).expect("example directory") {
        let path = entry.expect("example entry").path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("json") { continue; }
        let value = serde_json::from_slice(&fs::read(&path).expect("read fixture")).expect("fixture JSON");
        let publication = write_publication(&workspace, value);
        let output = workspace.run(&["panel", "validate", publication.to_str().expect("UTF-8 path")]);
        assert_eq!(output.code, 0, "{}: {}", path.display(), output.stderr);
        assert_eq!(output.stdout.trim(), "valid");
        count += 1;
    }
    assert!(count > 0, "no panel examples checked");
    cleanup(workspace);
}

#[test]
fn help_routes_reports_to_send_and_panels_to_live_state() {
    let workspace = Sandbox::new();
    let peer = Sandbox::new();
    assert_ne!(workspace.home, peer.home, "simultaneous workspaces must be distinct");
    cleanup(peer);
    for (arguments, expected) in [
        (vec!["send", "--help"], "Send a message, progress note, result or report to your boss"),
        (vec!["panel", "--help"], "Display live state the boss can watch change in panels"),
        (vec!["panel", "publish", "--help"], "For live state only; a report is `hiboss send`."),
    ] {
        let output = workspace.run(&arguments);
        assert_eq!(output.code, 0);
        let help = &output.stdout;
        assert!(help.contains(expected), "{help}");
    }
    cleanup(workspace);
}
