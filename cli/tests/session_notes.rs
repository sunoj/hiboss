// Exercises note commands and hook polling through the built CLI and mock HTTP.
// Covers read batching, local announcements, private state, TTLs and Codex context.
mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, read, wait_until, write_private};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

const ENV: &[(&str, &str)] = &[
    ("CLAUDECODE", "1"),
    ("CLAUDE_CODE_SESSION_ID", "notes"),
    ("HIBOSS_PROFILE", "claude"),
];

fn notes(count: usize) -> Value {
    json!({"notes": (0..count).map(|i| json!({
        "id": format!("note-{i}"), "session_id": "sid", "agent_id": "a1", "boss_name": "Boss",
        "body": "first line\nfull second line", "status": "pending",
        "created_at": "2026-11-02 10:00:00", "read_at": null,
    })).collect::<Vec<_>>()})
}

fn server(count: usize, read_status: u16) -> Http {
    Http::start(move |r: &Request| {
        if r.path.contains("/notes?") {
            return Response::json(200, notes(count));
        }
        if r.path.ends_with("/notes/read") {
            return Response::json(
                read_status,
                json!({"read": r.body["ids"].as_array().map(Vec::len)}),
            );
        }
        Response::json(200, json!({"sessions": [], "messages": [], "total": 0}))
    })
}

fn prepare(fixture: &Fixture) -> std::path::PathBuf {
    let dir = fixture.prepare("claude", "notes");
    write_private(&dir.join("session"), "sid");
    dir
}

fn prime_ttls(dir: &Path) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_secs();
    for name in ["a2a-check", "urgent-check", "note-check"] {
        write_private(&dir.join(name), &now.to_string());
    }
}

#[test]
fn note_read_prints_all_bodies_and_acknowledges_in_batches_of_fifty() {
    let http = server(51, 200);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "read", "--json"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    let output: Value = serde_json::from_str(&result.stdout).expect("JSON notes");
    assert_eq!(output["notes"].as_array().expect("notes").len(), 51);
    assert_eq!(output["notes"][50]["body"], "first line\nfull second line");
    let requests = http.requests();
    let marks: Vec<_> = requests
        .iter()
        .filter(|r| r.path.ends_with("/notes/read"))
        .collect();
    assert_eq!(marks.len(), 2);
    assert_eq!(marks[0].body["ids"].as_array().expect("batch").len(), 50);
    assert_eq!(marks[1].body["ids"], json!(["note-50"]));
    assert!(
        requests
            .iter()
            .all(|r| r.path.starts_with("/api/sessions/sid/notes"))
    );
}

#[test]
fn note_list_preserves_full_text_and_never_marks_read() {
    let http = server(1, 200);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "list", "--all"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    assert!(result.stdout.contains("Boss · 2026-11-02 10:00:00"));
    assert!(result.stdout.contains("first line\nfull second line"));
    let requests = http.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].path, "/api/sessions/sid/notes?status=all");
    assert_eq!(requests[0].method, "GET");
}

#[test]
fn note_read_clearly_reports_empty_and_propagates_acknowledgement_errors() {
    let http = server(0, 200);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "read"], ENV);
    assert_eq!(result.code, 0);
    assert!(result.stdout.contains("No pending notes"));
    assert!(http.requests().iter().all(|r| r.method == "GET"));
    let http = server(1, 500);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "read"], ENV);
    assert_ne!(result.code, 0);
    assert!(result.stdout.contains("full second line"));
}

#[test]
fn bg_check_writes_private_ids_and_post_tool_use_announces_without_http() {
    use std::os::unix::fs::PermissionsExt;
    let http = server(1, 200);
    let fixture = Fixture::new("repo", &http.url);
    let dir = prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["hook", "bg-check"], ENV);
    assert_eq!(result.code, 0);
    let pending = dir.join("note-pending");
    let stored: Value = serde_json::from_str(&read(&pending)).expect("pending state");
    assert_eq!(stored, json!({"session": "sid", "ids": ["note-0"], "images": 0}));
    assert_eq!(
        std::fs::metadata(&pending).expect("state").permissions().mode() & 0o777,
        0o600
    );
    // Stop the mock server before PostToolUse; all HTTP must already be complete.
    let requests = http.requests();
    assert_eq!(requests.iter().filter(|r| r.path.contains("/notes?")).count(), 1);
    prime_ttls(&dir);
    let first = fixture.run(&fixture.repo, &["hook", "post-tool-use"], ENV);
    assert!(first.stdout.contains("BOSS NOTE (留言): the boss left 1 note(s)"));
    let second = fixture.run(&fixture.repo, &["hook", "post-tool-use"], ENV);
    assert!(!second.stdout.contains("BOSS NOTE"));
    let mut announced: Value = serde_json::from_str(&read(&dir.join("note-announced"))).expect("notice");
    announced["at"] = json!(0);
    write_private(&dir.join("note-announced"), &announced.to_string());
    let repeat = fixture.run(&fixture.repo, &["hook", "post-tool-use"], ENV);
    assert!(repeat.stdout.contains("BOSS NOTE"));
    write_private(
        &pending,
        &json!({"session": "foreign", "ids": ["new"]}).to_string(),
    );
    let stale = fixture.run(&fixture.repo, &["hook", "post-tool-use"], ENV);
    assert!(!stale.stdout.contains("BOSS NOTE"));
}

#[test]
fn note_ttl_alone_spawns_detached_polling_with_codex_context() {
    let http = server(1, 200);
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("codex", "notes-thread");
    write_private(&dir.join("session"), "sid");
    prime_ttls(&dir);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_secs();
    write_private(&dir.join("note-check"), &now.saturating_sub(16).to_string());
    let env = [("CODEX_THREAD_ID", "notes-thread"), ("HIBOSS_PROFILE", "codex")];
    let result = fixture.run(&fixture.repo, &["hook", "post-tool-use"], &env);
    assert_eq!(result.code, 0);
    assert!(
        wait_until(|| dir.join("note-pending").exists()),
        "detached note polling did not run"
    );
    let stored: Value = serde_json::from_str(&read(&dir.join("note-pending"))).expect("state");
    assert_eq!(stored["session"], "sid");
    let requests = http.requests();
    let poll = requests
        .iter()
        .find(|r| r.path.contains("/notes?"))
        .expect("notes poll");
    assert_eq!(poll.header("authorization"), Some("Bearer synthetic-codex-key"));
}

#[test]
fn session_start_also_announces_pending_notes() {
    let http = server(1, 200);
    let fixture = Fixture::new("repo", &http.url);
    let result = fixture.run(&fixture.repo, &["hook", "session-start"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    assert!(result.stdout.contains("BOSS NOTE (留言)"));
}

#[path = "session_notes_images/mod.rs"]
mod images;
