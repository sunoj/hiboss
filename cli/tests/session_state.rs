// Drives the built CLI and its real daemon against a mock server to verify session state.
// Covers fail-closed state validation, exact self-heal, daemon restart, hooks and bare repos.
// Dependencies: session_identity_support (git sandbox + mock HTTP), serde_json.

mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, Run, is_hiboss, read, wait_until, write_private};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

const FOREIGN: &str = "session does not belong to calling agent";
const SPOOLED: &str = r#"{"id":"msg-boss-0001","direction":"boss_to_agent","agent_name":"boss","body":"ship it"}"#;

/// Rejects `foreign-session` with `rejection`; the first stream GET delivers one SSE message.
fn server(rejection: Response) -> Http {
    let rejection = (rejection.status, rejection.body);
    let delivered = Arc::new(AtomicBool::new(false));
    Http::start(move |request: &Request| match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/sessions") => Response::json(201, json!({"ok": true})),
        ("POST", "/api/messages") if request.body["session_id"] == "foreign-session" => {
            Response::json(rejection.0, rejection.1.clone())
        }
        ("POST", "/api/messages") => Response::json(
            201,
            json!({"id": "msg_1", "status": "sent", "created_at": "2026-10-03T00:00:00Z", "warning": null}),
        ),
        ("GET", path) if path.starts_with("/api/messages/stream") && !delivered.swap(true, Ordering::SeqCst) => {
            Response::json(200, Value::String(format!("event: message\ndata: {SPOOLED}\n\n")))
        }
        _ => Response::json(200, json!({"sessions": [], "messages": [], "total": 0})),
    })
}

fn foreign_400() -> Response {
    Response::json(400, json!(FOREIGN))
}

fn claude(fixture: &Fixture, args: &[&str], profile: &str) -> Run {
    let env = [("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s"), ("HIBOSS_PROFILE", profile)];
    fixture.run(&fixture.repo, args, &env)
}

fn posts<'a>(requests: &'a [Request], path: &str) -> Vec<&'a Value> {
    let posted = requests.iter().filter(|r| r.method == "POST" && r.path == path);
    posted.map(|r| &r.body).collect()
}

fn lines_with(text: &str, needle: &str) -> usize {
    text.lines().filter(|line| line.contains(needle)).count()
}

fn running_daemon(fixture: &Fixture, dir: &std::path::Path) -> u32 {
    let pid = read(&dir.join("daemon.pid")).parse().expect("daemon pid");
    assert!(wait_until(|| is_hiboss(pid)), "daemon {pid} is not running");
    assert!(fixture.daemon_pids().contains(&pid));
    pid
}

#[test]
fn linked_state_directory_falls_back_to_unscoped_operation() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let leaf = fixture.state_dir("claude", "s");
    let elsewhere = fixture.root.join("elsewhere");
    std::fs::create_dir_all(leaf.parent().expect("project dir")).expect("project dir");
    std::fs::create_dir(&elsewhere).expect("link target");
    std::os::unix::fs::symlink(&elsewhere, &leaf).expect("symlink");
    let start = claude(&fixture, &["hook", "session-start"], "claude");
    assert_eq!(start.code, 0, "{}", start.stderr);
    let send = claude(&fixture, &["send", "hello"], "claude");
    assert_eq!(send.code, 0, "{}", send.stderr);
    assert_eq!(lines_with(&send.stderr, "is unusable"), 1, "{}", send.stderr);
    assert!(send.stderr.contains(&leaf.display().to_string()), "{}", send.stderr);
    assert_eq!(std::fs::read_dir(&elsewhere).expect("target").count(), 0, "nothing created through the link");
    let requests = http.requests();
    assert!(posts(&requests, "/api/sessions").is_empty(), "no session without state");
    let sends = posts(&requests, "/api/messages");
    assert!(sends.len() == 1 && sends[0]["session_id"].is_null(), "unscoped send");
}

#[test]
fn linked_session_file_is_refused_and_left_untouched() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let session = fixture.prepare("claude", "s").join("session");
    let planted = fixture.root.join("planted");
    write_private(&planted, "planted-session");
    std::os::unix::fs::symlink(&planted, &session).expect("symlink");
    let send = claude(&fixture, &["send", "hello"], "claude");
    assert_eq!(send.code, 0, "{}", send.stderr);
    assert_eq!(lines_with(&send.stderr, "refusing session state file"), 1, "{}", send.stderr);
    assert!(send.stderr.contains(&session.display().to_string()), "{}", send.stderr);
    assert_eq!(read(&planted), "planted-session");
    let requests = http.requests();
    assert!(posts(&requests, "/api/messages")[0]["session_id"].is_null());
}

#[test]
fn refused_pid_file_starts_no_listener() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    std::fs::create_dir(dir.join("daemon.pid")).expect("unwritable pid file");
    let start = claude(&fixture, &["hook", "session-start"], "claude");
    assert_eq!(start.code, 0, "{}", start.stderr);
    assert_eq!(lines_with(&start.stderr, "daemon start failed"), 1, "{}", start.stderr);
    let direct = claude(&fixture, &["daemon", "start"], "claude");
    assert_ne!(direct.code, 0, "{}", direct.stderr);
    assert!(!dir.join("daemon.log").exists(), "nothing was spawned");
    std::thread::sleep(std::time::Duration::from_millis(500));
    let subscribed = http.paths().into_iter().filter(|path| path.contains("/api/messages/stream"));
    assert_eq!(subscribed.count(), 0, "no listener subscribed");
}

#[test]
fn only_the_exact_400_rejection_heals() {
    for rejection in [
        Response::json(500, json!(FOREIGN)),
        Response::json(400, json!(format!("{FOREIGN}: and more"))),
        Response::json(400, json!({"error": FOREIGN})),
    ] {
        let http = server(rejection);
        let fixture = Fixture::new("repo", &http.url);
        write_private(&fixture.prepare("claude", "s").join("session"), "foreign-session");
        let send = claude(&fixture, &["send", "hello"], "claude");
        assert_ne!(send.code, 0, "{}", send.stderr);
        assert_eq!(lines_with(&send.stderr, "belonged to another agent"), 0, "{}", send.stderr);
        let requests = http.requests();
        assert!(posts(&requests, "/api/sessions").is_empty());
        assert_eq!(posts(&requests, "/api/messages").len(), 1, "no retry");
    }
}

#[test]
fn heal_restarts_the_daemon_on_the_new_session() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let start = claude(&fixture, &["hook", "session-start"], "claude");
    assert_eq!(start.code, 0, "{}", start.stderr);
    let before = running_daemon(&fixture, &dir);
    write_private(&dir.join("session"), "foreign-session");
    let send = claude(&fixture, &["send", "hello"], "claude");
    assert_eq!(send.code, 0, "{}", send.stderr);
    assert_eq!(lines_with(&send.stderr, "belonged to another agent"), 1, "{}", send.stderr);
    let fresh = read(&dir.join("session"));
    let after = running_daemon(&fixture, &dir);
    assert_ne!(before, after, "the daemon was restarted");
    assert!(wait_until(|| !is_hiboss(before)), "the old daemon was stopped");
    let subscribed = format!("GET /api/messages/stream?session={fresh}");
    assert!(wait_until(|| http.paths().contains(&subscribed)), "{:?}", http.paths());
}

#[test]
fn post_tool_use_drains_only_its_own_profiles_spool() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let start = claude(&fixture, &["hook", "session-start"], "claude");
    assert_eq!(start.code, 0, "{}", start.stderr);
    let spool = dir.join("daemon.pending");
    assert!(wait_until(|| spool.exists()), "the daemon spooled the SSE message");
    let other = claude(&fixture, &["hook", "post-tool-use"], "codex");
    assert_eq!(other.code, 0, "{}", other.stderr);
    assert!(!other.stdout.contains("ship it"), "{}", other.stdout);
    let own = claude(&fixture, &["hook", "post-tool-use"], "claude");
    assert_eq!(own.code, 0, "{}", own.stderr);
    assert!(own.stdout.contains("[boss] boss (msg-boss): ship it"), "{}", own.stdout);
    assert!(!spool.exists(), "the spool was drained");
    let marked = |paths: Vec<String>| paths.iter().any(|path| path.contains("msg-boss-0001"));
    assert!(wait_until(|| marked(http.paths())), "bg-check marks the shown message read");
}

#[test]
fn interactive_stop_parks_the_session_as_waiting() {
    let http = server(foreign_400());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let start = claude(&fixture, &["hook", "session-start"], "claude");
    assert_eq!(start.code, 0, "{}", start.stderr);
    let daemon = running_daemon(&fixture, &dir);
    let stop = claude(&fixture, &["hook", "stop"], "claude");
    assert_eq!(stop.code, 0, "{}", stop.stderr);
    assert!(dir.join("resume-pending").exists());
    assert!(!dir.join("daemon.pid").exists());
    assert!(wait_until(|| !is_hiboss(daemon)), "Stop stops the daemon");
    let session = read(&dir.join("session"));
    let requests = http.requests();
    let parked = requests.iter().find(|r| r.method == "PATCH" && r.path == format!("/api/sessions/{session}"));
    assert_eq!(parked.map(|r| &r.body["status"]), Some(&json!("waiting")));
}

#[test]
fn bare_repository_worktree_is_named_by_the_repository() {
    let http = server(foreign_400());
    let fixture = Fixture::new("seed", &http.url);
    let work = fixture.root.join("work");
    std::fs::create_dir(&work).expect("work dir");
    let seed = fixture.repo.to_str().expect("utf8");
    fixture.git(&work, &["clone", "-q", "--bare", seed, "alpha.git"]);
    let bare = work.join("alpha.git");
    fixture.git(&bare, &["remote", "remove", "origin"]);
    let tree = fixture.root.join("zzz-tree");
    fixture.git(&bare, &["worktree", "add", "-q", "-b", "feature", tree.to_str().expect("utf8")]);
    let env = [("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s"), ("HIBOSS_PROFILE", "claude")];
    let run = fixture.run(&tree, &["hook", "session-start"], &env);
    assert_eq!(run.code, 0, "{}", run.stderr);
    let requests = http.requests();
    let registered = posts(&requests, "/api/sessions");
    assert_eq!(registered[0]["project"], "alpha");
    assert_eq!(registered[0]["project_identity"]["aliases"], json!(["alpha"]));
}
