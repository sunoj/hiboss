// Exercises Codex identity selection and isolated project/session registration.
// Uses the built CLI against a synthetic server with distinct credential profiles.

mod session_identity_support;
use serde_json::json;
use session_identity_support::{
    Fixture,
    http::{Http, Response},
    read,
};
use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn codex_selects_its_identity_and_registers_each_thread_under_house() {
    let http = Http::start(|_| {
        Response::json(
            201,
            json!({"ok":true, "sessions":[], "messages":[], "total":0}),
        )
    });
    let fixture = Fixture::new("house", &http.url);
    for thread in ["codex-one", "codex-two"] {
        let env = [("CODEX_THREAD_ID", thread)];
        let identity = fixture.run(&fixture.repo, &["whoami", "--json"], &env);
        let value: serde_json::Value = serde_json::from_str(&identity.stdout).expect("identity");
        assert_eq!(value["runtime"], "codex");
        assert_eq!(value["profile"], "codex");
        let start = fixture.run(&fixture.repo, &["hook", "session-start"], &env);
        assert_eq!(start.code, 0, "{}", start.stderr);
        assert!(!read(&fixture.state_dir("codex", thread).join("session")).is_empty());
    }
    let requests = http.requests();
    let registrations: Vec<_> = requests
        .iter()
        .filter(|r| r.method == "POST" && r.path == "/api/sessions")
        .collect();
    assert_eq!(registrations.len(), 2);
    assert_ne!(registrations[0].body["id"], registrations[1].body["id"]);
    for request in registrations {
        assert_eq!(request.body["project"], "house");
        assert_eq!(request.body["runtime"], "codex");
        assert_eq!(
            request.header("authorization"),
            Some("Bearer synthetic-codex-key")
        );
    }
}

#[test]
fn codex_send_registers_the_project_when_the_start_hook_has_not_run() {
    let http = Http::start(|request| match request.path.as_str() {
        "/api/messages" if request.method == "POST" => Response::json(
            201,
            json!({"id":"m", "status":"sent", "created_at":"2026-10-11T00:00:00Z"}),
        ),
        _ => Response::json(200, json!({"ok":true, "messages":[], "total":0})),
    });
    let fixture = Fixture::new("house", &http.url);
    let run = fixture.run(
        &fixture.repo,
        &["send", "House update", "--content", "**Done**"],
        &[("CODEX_SESSION_ID", "codex-send")],
    );
    assert_eq!(run.code, 0, "{}", run.stderr);
    let requests = http.requests();
    let registered = requests
        .iter()
        .find(|r| r.path == "/api/sessions")
        .expect("registration");
    let sent = requests
        .iter()
        .find(|r| r.method == "POST" && r.path == "/api/messages")
        .expect("message");
    assert_eq!(registered.body["project"], "house");
    assert_eq!(sent.body["session_id"], registered.body["id"]);
    assert_eq!(
        sent.header("authorization"),
        Some("Bearer synthetic-codex-key")
    );
}

#[test]
fn codex_hook_installation_preserves_other_hooks_and_is_idempotent() {
    let fixture = Fixture::new("house", "https://example.test");
    let directory = fixture.root.join("codex-config");
    std::fs::create_dir(&directory).expect("directory");
    let path = directory.join("hooks.json");
    let existing = json!({"hooks":{"SessionStart":[{"hooks":[
        {"type":"command", "command":"existing-check", "timeout":10}]}]}});
    std::fs::write(&path, existing.to_string()).expect("settings");
    let environment = [("CODEX_HOME", directory.to_str().expect("directory"))];
    let command = ["setup", "hooks", "--runtime", "codex", "--global"];
    let installed = fixture.run(&fixture.repo, &command, &environment);
    assert_eq!(installed.code, 0, "{}", installed.stderr);
    assert!(installed.stdout.contains("/hooks"));
    let first = std::fs::read_to_string(&path).expect("installed");
    let value: serde_json::Value = serde_json::from_str(&first).expect("JSON");
    assert_eq!(
        value["hooks"]["SessionStart"][0]["hooks"][0]["command"],
        "existing-check"
    );
    assert_eq!(
        value["hooks"]["SessionStart"][1]["hooks"][0]["command"],
        "HIBOSS_PROFILE=codex hiboss hook --codex-input session-start"
    );
    let repeated = fixture.run(&fixture.repo, &command, &environment);
    assert_eq!(repeated.code, 0, "{}", repeated.stderr);
    assert_eq!(std::fs::read_to_string(&path).expect("repeated"), first);
    let removed = fixture.run(
        &fixture.repo,
        &[
            "setup",
            "hooks",
            "--runtime",
            "codex",
            "--global",
            "--remove",
        ],
        &environment,
    );
    assert_eq!(removed.code, 0, "{}", removed.stderr);
    let value: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(path).expect("remaining settings"))
            .expect("JSON");
    assert_eq!(value, existing);
}

#[test]
fn codex_hook_uses_the_json_project_and_emits_model_visible_context() {
    let http = Http::start(|_| {
        Response::json(
            200,
            json!({"ok":true, "sessions":[], "messages":[], "total":0}),
        )
    });
    let fixture = Fixture::new("house", &http.url);
    let mut child = Command::new(env!("CARGO_BIN_EXE_hiboss"))
        .args(["hook", "--codex-input", "session-start"])
        .env_clear()
        .env("HOME", &fixture.root)
        .env("PATH", "/usr/bin:/bin")
        .env("HIBOSS_CONFIG", fixture.config())
        .env("NO_PROXY", "127.0.0.1")
        .current_dir(&fixture.root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("hook");
    let input = json!({"session_id":"codex-hook", "cwd":fixture.repo,
        "hook_event_name":"SessionStart"});
    child
        .stdin
        .take()
        .expect("input")
        .write_all(input.to_string().as_bytes())
        .expect("write");
    let output = child.wait_with_output().expect("result");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).expect("hook JSON");
    assert_eq!(value["hookSpecificOutput"]["hookEventName"], "SessionStart");
    assert!(
        value["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .is_some_and(|text| text.contains("144") && text.contains("--content-file"))
    );
    let requests = http.requests();
    let registered = requests
        .iter()
        .find(|r| r.path == "/api/sessions")
        .expect("registration");
    assert_eq!(registered.body["project"], "house");
    assert_eq!(registered.body["runtime"], "codex");
}
