// Exercises doctor profile coverage and current-Claude-only hook failures.
// Uses the built CLI with isolated HOME and synthetic healthy HTTP responses.
// Dependencies: session_identity_support, serde_json, filesystem.

mod session_identity_support;

use serde_json::json;
use session_identity_support::{
    Fixture,
    http::{Http, Request, Response},
};
use std::fs;

fn healthy(request: &Request) -> Response {
    let body = match request.path.as_str() {
        "/api/agents/me" => json!({"name":"test", "channel_routing":{}}),
        "/api/channels" => json!({"channels":[]}),
        "/api/channels/stats" => json!({"channels":[], "recent_errors":[], "direction_counts":[]}),
        _ => json!({}),
    };
    Response::json(200, body)
}

#[test]
fn doctor_lists_every_profile_but_missing_inactive_hooks_do_not_fail() {
    let http = Http::start(healthy);
    let fixture = Fixture::new("doctor", &http.url);
    fs::create_dir_all(fixture.root.join(".claude-m/projects")).expect("profile");
    let current = fixture.root.join(".claude");
    let current = current.to_str().expect("path");
    let install = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--config-dir", current],
        &[],
    );
    assert_eq!(install.code, 0, "{}", install.stderr);
    let out = fixture.run(&fixture.repo, &["doctor"], &[("CLAUDECODE", "1")]);
    assert_eq!(out.code, 0, "{} {}", out.stdout, out.stderr);
    assert!(
        out.stdout
            .contains(&format!("Claude profile {current}: hooks installed"))
    );
    let inactive = fixture.root.join(".claude-m");
    assert!(out.stdout.contains(&format!(
        "Claude profile {}: hooks missing",
        inactive.display()
    )));
    assert!(out.stdout.contains(&format!(
        "hiboss setup hooks --global --config-dir '{}'",
        inactive.display()
    )));
}

#[test]
fn doctor_missing_current_hooks_fail_only_inside_claude() {
    let http = Http::start(healthy);
    let fixture = Fixture::new("doctor", &http.url);
    let current = fixture.root.join(".claude-second");
    let current = current.to_str().expect("path");
    let outside = fixture.run(
        &fixture.repo,
        &["doctor"],
        &[("CLAUDE_CONFIG_DIR", current)],
    );
    assert_eq!(outside.code, 0, "{} {}", outside.stdout, outside.stderr);
    for signal in [("CLAUDECODE", "1"), ("CLAUDE_CODE_ENTRYPOINT", "cli")] {
        let out = fixture.run(
            &fixture.repo,
            &["doctor"],
            &[("CLAUDE_CONFIG_DIR", current), signal],
        );
        assert_ne!(out.code, 0, "{}", out.stdout);
        assert!(
            out.stdout
                .contains(&format!("Claude profile {current}: hooks missing"))
        );
        assert!(out.stdout.contains(&format!(
            "hiboss setup hooks --global --config-dir '{current}'"
        )));
    }
    let install = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--config-dir", current],
        &[],
    );
    assert_eq!(install.code, 0, "{}", install.stderr);
    let out = fixture.run(
        &fixture.repo,
        &["doctor"],
        &[("CLAUDE_CONFIG_DIR", current), ("CLAUDECODE", "1")],
    );
    assert_eq!(out.code, 0, "{} {}", out.stdout, out.stderr);
}

#[test]
fn doctor_partial_or_disabled_hooks_are_missing() {
    let http = Http::start(healthy);
    let fixture = Fixture::new("doctor", &http.url);
    let current = fixture.root.join(".claude");
    fs::create_dir_all(&current).expect("profile");
    fs::write(
        current.join("settings.json"),
        r#"{"hooks":{"SessionStart":[{"hooks":[
        {"type":"command","command":"hiboss hook session-start"}]}]}}"#,
    )
    .expect("partial");
    let out = fixture.run(&fixture.repo, &["doctor"], &[("CLAUDECODE", "1")]);
    assert_ne!(out.code, 0);
    let install = fixture.run(&fixture.repo, &["setup", "hooks", "--global"], &[]);
    assert_eq!(install.code, 0, "{}", install.stderr);
    let path = current.join("settings.json");
    let mut settings: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&path).expect("settings")).expect("JSON");
    settings["disableAllHooks"] = json!(true);
    fs::write(path, settings.to_string()).expect("disabled");
    assert_ne!(
        fixture
            .run(&fixture.repo, &["doctor"], &[("CLAUDECODE", "1")])
            .code,
        0
    );
}
