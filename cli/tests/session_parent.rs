// Drives the built CLI against a mock server to verify how a dispatched (aid) session picks
// its parent: the newest non-dispatched sibling session in the same project, or none.
// Dependencies: session_identity_support (git sandbox + mock HTTP), serde_json.

mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, read, write_private};
use std::time::{Duration, SystemTime};

const REJECTED: &str = "hiboss: the server rejected the parent session; registered without a parent";

/// Accepts registrations, flagging any parent as rejected when `reject` is set.
fn server(reject: bool) -> Http {
    Http::start(move |request: &Request| match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/sessions") if reject && request.body.get("parent_session_id").is_some() => {
            Response::json(201, json!({"ok": true, "parent_rejected": true}))
        }
        ("POST", "/api/sessions") => Response::json(201, json!({"ok": true})),
        _ => Response::json(200, json!({"sessions": [], "messages": [], "total": 0})),
    })
}

fn registrations(http: Http) -> Vec<Value> {
    let requests = http.requests();
    let posts = requests.into_iter().filter(|r| r.method == "POST" && r.path == "/api/sessions");
    posts.map(|request| request.body).collect()
}

/// Runs SessionStart for a Claude session (or an aid task when `task` is set); returns the id.
fn start(fixture: &Fixture, key: &str, task: bool) -> (String, String) {
    let dir = fixture.prepare("claude", key);
    let mut env = vec![("CLAUDECODE", "1"), ("HIBOSS_PROFILE", "claude")];
    env.push(if task { ("AID_TASK_ID", key) } else { ("CLAUDE_CODE_SESSION_ID", key) });
    let run = fixture.run(&fixture.repo, &["hook", "session-start"], &env);
    assert_eq!(run.code, 0, "{}", run.stderr);
    assert!(!run.stderr.contains("registration failed"), "{}", run.stderr);
    (read(&dir.join("session")), run.stderr)
}

/// Sets the mtime of a session directory's `session` file to `age` seconds ago.
fn touch(fixture: &Fixture, key: &str, age: u64) {
    let path = fixture.state_dir("claude", key).join("session");
    let file = std::fs::File::options().write(true).open(&path).expect("session file");
    file.set_modified(SystemTime::now() - Duration::from_secs(age)).expect("mtime");
}

#[test]
fn aid_registers_under_the_claude_session_of_the_same_project() {
    let http = server(false);
    let fixture = Fixture::new("repo", &http.url);
    let (parent, _) = start(&fixture, "s1", false);
    let (child, stderr) = start(&fixture, "task-1", true);
    assert!(!stderr.contains(REJECTED), "{stderr}");
    let registered = registrations(http);
    assert!(registered[0].get("parent_session_id").is_none(), "only aid sends a parent");
    assert_eq!(registered[1]["id"], child.as_str());
    assert_eq!(registered[1]["parent_session_id"], parent.as_str());
}

#[test]
fn aid_without_a_marked_sibling_registers_without_a_parent() {
    let http = server(false);
    let fixture = Fixture::new("repo", &http.url);
    let legacy = fixture.prepare("claude", "legacy");
    write_private(&legacy.join("session"), "sess-legacy");
    start(&fixture, "task-1", true);
    let registered = registrations(http);
    assert_eq!(registered.len(), 1);
    assert_eq!(registered[0]["runtime"], "aid");
    assert!(registered[0].get("parent_session_id").is_none(), "{}", registered[0]);
}

#[test]
fn the_most_recently_touched_of_two_claude_sessions_wins() {
    let http = server(false);
    let fixture = Fixture::new("repo", &http.url);
    let (first, _) = start(&fixture, "s1", false);
    start(&fixture, "s2", false);
    touch(&fixture, "s1", 10);
    touch(&fixture, "s2", 300);
    start(&fixture, "task-1", true);
    let registered = registrations(http);
    assert_eq!(registered[2]["parent_session_id"], first.as_str(), "mtime, not registration order");
}

#[test]
fn a_dispatched_sibling_is_never_the_parent() {
    let http = server(false);
    let fixture = Fixture::new("repo", &http.url);
    let (parent, _) = start(&fixture, "s1", false);
    touch(&fixture, "s1", 300);
    let (peer, _) = start(&fixture, "task-1", true);
    start(&fixture, "task-2", true);
    let registered = registrations(http);
    assert_eq!(registered[2]["parent_session_id"], parent.as_str());
    assert_ne!(registered[2]["parent_session_id"], peer.as_str());
    let marker = |key: &str| read(&fixture.state_dir("claude", key).join("runtime"));
    assert_eq!((marker("s1").as_str(), marker("task-1").as_str()), ("claude", "aid"));
}

#[test]
fn a_rejected_parent_warns_once_on_stderr_and_registration_succeeds() {
    let http = server(true);
    let fixture = Fixture::new("repo", &http.url);
    start(&fixture, "s1", false);
    let dir = fixture.prepare("claude", "task-1");
    let env = [("AID_TASK_ID", "task-1"), ("CLAUDECODE", "1"), ("HIBOSS_PROFILE", "claude")];
    let run = fixture.run(&fixture.repo, &["hook", "session-start"], &env);
    assert_eq!(run.code, 0, "{}", run.stderr);
    assert_eq!(run.stderr.matches(REJECTED).count(), 1, "{}", run.stderr);
    assert!(!run.stdout.contains("rejected the parent"), "{}", run.stdout);
    assert!(!read(&dir.join("session")).is_empty());
}
