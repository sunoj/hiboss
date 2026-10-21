// Drives nickname registration, healing, heartbeat persistence, and CLI output through mock HTTP.
// Depends on the built CLI and the existing isolated session identity fixture.
mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, read, write_private};

const SESSION_ENV: &[(&str, &str)] = &[
    ("CLAUDECODE", "1"),
    ("CLAUDE_CODE_SESSION_ID", "nickname-test"),
    ("HIBOSS_PROFILE", "claude"),
];

fn server() -> Http {
    Http::start(
        |request: &Request| match (request.method.as_str(), request.path.as_str()) {
            ("POST", "/api/sessions") => Response::json(
                201,
                json!({
                    "nickname": format!("{}-2", request.body["nickname"].as_str().expect("chosen nickname")),
                }),
            ),
            ("PATCH", _) => Response::json(200, json!({"ok": true, "nickname": "coral-3"})),
            ("POST", "/api/messages") if request.body["session_id"] == "foreign-session" => {
                Response::json(400, json!("session does not belong to calling agent"))
            }
            ("POST", "/api/messages") => Response::json(
                201,
                json!({
                    "id": "msg_1", "status": "sent", "created_at": "2026-10-10T00:00:00Z", "warning": null,
                    "target": {"id": "peer-session-123", "label": "repo/main", "nickname": "coral-2"},
                }),
            ),
            ("GET", "/api/sessions") => Response::json(
                200,
                json!({"sessions": [
                    {"id": "peer-session-123", "agent_id": "a1", "label": "repo/main", "nickname": "coral-2"},
                    {"id": "legacy-peer", "agent_id": "a1", "label": "legacy/main"},
                ]}),
            ),
            _ => Response::json(200, json!({"sessions": [], "messages": [], "total": 0})),
        },
    )
}

#[test]
fn registration_saves_the_server_suffix_and_heartbeats_reuse_and_update_it() {
    let http = server();
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "nickname-test");
    let start = fixture.run(&fixture.repo, &["hook", "session-start"], SESSION_ENV);
    assert_eq!(start.code, 0, "{}", start.stderr);
    assert!(!start.stderr.contains("registration failed"), "{}", start.stderr);
    let id = read(&dir.join("session"));
    let after_registration: Value =
        serde_json::from_str(&read(&dir.join("nickname"))).expect("saved nickname");
    for _ in 0..2 {
        let update = fixture.run(&fixture.repo, &["ss", "set", "working"], SESSION_ENV);
        assert_eq!(update.code, 0, "{}", update.stderr);
    }
    // `requests()` stops the mock server, so it is read once, after every call.
    let requests = http.requests();
    let registration = requests
        .iter()
        .find(|r| r.method == "POST" && r.path == "/api/sessions")
        .expect("registration");
    let chosen = registration.body["nickname"].as_str().expect("chosen word");
    assert!((3..=12).contains(&chosen.len()) && chosen.bytes().all(|b| b.is_ascii_lowercase()));
    assert_eq!(after_registration, json!({"id": id, "nickname": format!("{chosen}-2")}));
    let heartbeats: Vec<_> = requests.iter().filter(|r| r.method == "PATCH").collect();
    assert_eq!(heartbeats.len(), 2);
    assert_eq!(heartbeats[0].body["nickname"], format!("{chosen}-2"));
    assert_eq!(heartbeats[1].body["nickname"], "coral-3");
    let stored: Value = serde_json::from_str(&read(&dir.join("nickname"))).expect("accepted nickname");
    assert_eq!(stored, json!({"id": id, "nickname": "coral-3"}));
}

#[test]
fn an_existing_session_without_a_nickname_chooses_one_on_heartbeat() {
    let http = server();
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "nickname-test");
    write_private(&dir.join("session"), "existing-session");
    let update = fixture.run(&fixture.repo, &["ss", "set", "idle"], SESSION_ENV);
    assert_eq!(update.code, 0, "{}", update.stderr);
    let requests = http.requests();
    let heartbeat = requests.iter().find(|r| r.method == "PATCH").expect("heartbeat");
    let chosen = heartbeat.body["nickname"].as_str().expect("chosen nickname");
    assert!((3..=12).contains(&chosen.len()) && chosen.bytes().all(|b| b.is_ascii_lowercase()));
    let stored: Value = serde_json::from_str(&read(&dir.join("nickname"))).expect("saved nickname");
    assert_eq!(stored, json!({"id": "existing-session", "nickname": "coral-3"}));
}

#[test]
fn healing_chooses_a_fresh_word_for_the_new_id_and_saves_the_accepted_name() {
    let http = server();
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "nickname-test");
    write_private(&dir.join("session"), "foreign-session");
    write_private(
        &dir.join("nickname"),
        r#"{"id":"foreign-session","nickname":"otter-9"}"#,
    );
    let run = fixture.run(&fixture.repo, &["send", "--to", "coral-2", "hello"], SESSION_ENV);
    assert_eq!(run.code, 0, "{}", run.stderr);
    assert!(run.stderr.contains("registered session"), "{}", run.stderr);
    let id = read(&dir.join("session"));
    assert_ne!(id, "foreign-session");
    let requests = http.requests();
    let registration = requests
        .iter()
        .find(|r| r.path == "/api/sessions" && r.method == "POST")
        .expect("healed registration");
    let chosen = registration.body["nickname"].as_str().expect("fresh word");
    assert!(chosen.bytes().all(|b| b.is_ascii_lowercase()));
    let stored: Value = serde_json::from_str(&read(&dir.join("nickname"))).expect("healed nickname");
    assert_eq!(stored, json!({"id": id, "nickname": format!("{chosen}-2")}));
}

#[test]
fn status_board_and_send_output_show_nicknames() {
    let http = server();
    let fixture = Fixture::new("repo", &http.url);
    fixture.prepare("claude", "nickname-test");
    let board = fixture.run(&fixture.repo, &["ss"], SESSION_ENV);
    assert_eq!(board.code, 0, "{}", board.stderr);
    assert!(board.stdout.contains("repo/main · coral-2"), "{}", board.stdout);
    assert!(board.stdout.contains("legacy/main"), "{}", board.stdout);
    let sent = fixture.run(
        &fixture.repo,
        &["send", "--to", "repo/main", "hello"],
        SESSION_ENV,
    );
    assert_eq!(sent.code, 0, "{}", sent.stderr);
    assert!(
        sent.stdout.contains("sent -> coral-2 (peer-ses) id=msg_1"),
        "{}",
        sent.stdout
    );
}

#[test]
fn a_chosen_word_persists_across_cli_processes_when_the_server_returns_no_nickname() {
    let http = Http::start(|_| Response::json(200, json!({"ok": true})));
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "nickname-test");
    write_private(&dir.join("session"), "existing-session");
    for _ in 0..2 {
        let update = fixture.run(&fixture.repo, &["ss", "set", "working"], SESSION_ENV);
        assert_eq!(update.code, 0, "{}", update.stderr);
    }
    let requests = http.requests();
    let heartbeats: Vec<_> = requests.iter().filter(|r| r.method == "PATCH").collect();
    assert_eq!(heartbeats.len(), 2);
    assert_eq!(heartbeats[0].body["nickname"], heartbeats[1].body["nickname"]);
    let stored: Value = serde_json::from_str(&read(&dir.join("nickname"))).expect("saved word");
    assert_eq!(stored["nickname"], heartbeats[0].body["nickname"]);
    assert_eq!(stored["id"], "existing-session");
}
