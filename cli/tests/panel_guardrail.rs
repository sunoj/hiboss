// Purpose: Exercise live-state validation and help through the real CLI on a remote build box.
// Exports: CLI regression tests for static publication rejection and shipped examples.
// Dependencies: std, serde_json, and Cargo's built hiboss binary; no live server.

use serde_json::{Value, json};
use std::{fs, path::PathBuf, process::{Command, Output}, time::{SystemTime, UNIX_EPOCH}};

struct Workspace(PathBuf);

impl Workspace {
    fn new() -> Self {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).expect("clock").as_nanos();
        let path = std::env::temp_dir().join(format!("hiboss-guardrail-{}-{stamp}", std::process::id()));
        fs::create_dir_all(path.join("hiboss")).expect("isolated config directory");
        fs::write(path.join("hiboss/config.json"), r#"{"server":"http://127.0.0.1:1","key":"test-only"}"#)
            .expect("test config");
        Self(path)
    }

    fn run(&self, arguments: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_hiboss"))
            .env("XDG_CONFIG_HOME", &self.0)
            .current_dir(&self.0)
            .args(arguments).output().expect("run CLI")
    }

    fn write_publication(&self, mut value: Value) -> PathBuf {
        value["taskKey"] = json!("guardrail-test");
        value["sessionId"] = json!("guardrail-session");
        let path = self.0.join("publication.json");
        fs::write(&path, serde_json::to_vec(&value).expect("publication JSON")).expect("write publication");
        path
    }
}

impl Drop for Workspace {
    fn drop(&mut self) { fs::remove_dir_all(&self.0).expect("remove isolated workspace"); }
}

#[test]
fn validate_and_publish_reject_static_reports_before_network_access() {
    let workspace = Workspace::new();
    let value = json!({
        "protocolVersion": 2, "catalogId": "hiboss.panel", "catalogVersion": 1,
        "title": "Execution finished",
        "spec": {"root": "text", "elements": {
            "text": {"type": "Text", "props": {"text": "All tests passed"}, "children": []}
        }},
        "stateSchema": {"type": "object", "properties": {"task": {"type": "object"}}},
        "initialState": {"task": {}}
    });
    let path = workspace.write_publication(value);
    for command in ["validate", "publish"] {
        let output = workspace.run(&["panel", command, path.to_str().expect("UTF-8 path")]);
        assert!(!output.status.success(), "{command} accepted static content");
        assert_eq!(String::from_utf8_lossy(&output.stderr).trim(),
            "Error: invalid_spec at /spec/elements: no live state is bound; a card with only static content is a message — use hiboss send");
    }
}

#[test]
fn panel_validate_accepts_every_example_with_publication_identity() {
    let workspace = Workspace::new();
    let examples = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../panel-runtime/fixtures/examples");
    let mut count = 0;
    for entry in fs::read_dir(examples).expect("example directory") {
        let path = entry.expect("example entry").path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("json") { continue; }
        let value = serde_json::from_slice(&fs::read(&path).expect("read fixture")).expect("fixture JSON");
        let publication = workspace.write_publication(value);
        let output = workspace.run(&["panel", "validate", publication.to_str().expect("UTF-8 path")]);
        assert!(output.status.success(), "{}: {}", path.display(), String::from_utf8_lossy(&output.stderr));
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "valid");
        count += 1;
    }
    assert!(count > 0, "no panel examples checked");
}

#[test]
fn help_routes_reports_to_send_and_panels_to_live_state() {
    let workspace = Workspace::new();
    for (arguments, expected) in [
        (vec!["send", "--help"], "Send a message, progress note, result or report to your boss"),
        (vec!["panel", "--help"], "Display live state the boss can watch change in panels"),
        (vec!["panel", "publish", "--help"], "For live state only; a report is `hiboss send`."),
    ] {
        let output = workspace.run(&arguments);
        assert!(output.status.success());
        let help = String::from_utf8_lossy(&output.stdout);
        assert!(help.contains(expected), "{help}");
    }
}
