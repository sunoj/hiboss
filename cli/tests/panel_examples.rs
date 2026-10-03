// Purpose: Exercise offline example discovery, export, and validation via the CLI.
// Dependencies: compiled hiboss binary, serde_json, and isolated temporary files.

use std::process::Command;

#[test]
fn exports_all_examples_for_validation_and_reports_unknown_names() {
    let binary = env!("CARGO_BIN_EXE_hiboss");
    let listing = Command::new(binary).args(["panel", "example"]).output().expect("list examples");
    assert!(listing.status.success(), "{:?}", listing);
    let listing = String::from_utf8(listing.stdout).expect("UTF-8 listing");
    assert_eq!(listing.lines().count(), 4);
    for line in listing.lines() {
        let name = line.split(':').next().expect("example name");
        let output = Command::new(binary).args(["panel", "example", name]).output().expect("export");
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        let mut value: serde_json::Value = serde_json::from_slice(&output.stdout).expect("only JSON");
        for (key, identity) in [("taskKey", "example-check"), ("sessionId", "session_test"), ("targetBossId", "boss_test")] {
            value[key] = serde_json::json!(identity);
        }
        let path = std::env::temp_dir().join(format!("hiboss-example-{}-{name}.json", std::process::id()));
        std::fs::write(&path, value.to_string()).expect("write publication");
        let validated = Command::new(binary).args(["panel", "validate"]).arg(&path).output().expect("validate");
        std::fs::remove_file(path).expect("remove publication");
        assert!(validated.status.success(), "{name}: {:?}", validated);
        assert_eq!(validated.stdout, b"valid\n");
    }
    let unknown = Command::new(binary).args(["panel", "example", "unknown"]).output().expect("unknown name");
    assert!(!unknown.status.success());
    assert!(unknown.stdout.is_empty());
    assert!(String::from_utf8_lossy(&unknown.stderr).contains("hiboss panel example"));
    let help = Command::new(binary).args(["panel", "--help"]).output().expect("help");
    assert!(String::from_utf8_lossy(&help.stdout).contains("example"));
}

#[test]
fn denominator_warning_is_stderr_only_and_validation_still_passes() {
    let binary = env!("CARGO_BIN_EXE_hiboss");
    let output = Command::new(binary).args(["panel", "example", "download-progress"]).output().expect("export");
    let mut value: serde_json::Value = serde_json::from_slice(&output.stdout).expect("example JSON");
    value["taskKey"] = serde_json::json!("lint-check");
    value["sessionId"] = serde_json::json!("session_test");
    let path = std::env::temp_dir().join(format!("hiboss-denominator-{}.json", std::process::id()));
    for label in ["Downloaded GB / 787", "Downloaded GB"] {
        value["spec"]["elements"]["downloaded"]["props"]["label"] = serde_json::json!(label);
        std::fs::write(&path, value.to_string()).expect("write publication");
        let result = Command::new(binary).args(["panel", "validate"]).arg(&path).output().expect("validate");
        assert!(result.status.success());
        assert_eq!(result.stdout, b"valid\n");
        let expected = if label.contains('/') {
            format!("warning: Metric \"{label}\" carries a denominator; a real denominator is a Progress element\n")
        } else { String::new() };
        assert_eq!(String::from_utf8_lossy(&result.stderr), expected);
    }
    std::fs::remove_file(path).expect("remove publication");
}
