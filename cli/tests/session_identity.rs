// Drives the built CLI against a mock server to verify per-session state and identity.
// Covers profile-scoped state dirs, worktree project keys, self-heal, and dispatched mode.
// Dependencies: session_identity_support (git sandbox + mock HTTP), serde_json.

mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, read};

const FOREIGN: &str = "session does not belong to calling agent";

fn sent() -> Value {
    json!({"id": "msg_1", "direction": "agent_to_boss", "status": "sent", "metadata": {}, "replies": []})
}

/// Accepts registrations and sends; every read answers empty.
fn server() -> Http {
    Http::start(
        |request: &Request| match (request.method.as_str(), request.path.as_str()) {
            ("POST", "/api/sessions") => Response::json(201, json!({"ok": true})),
            ("POST", "/api/messages") if request.body["session_id"] == "foreign-session" => {
                Response::json(400, json!(FOREIGN))
            }
            ("POST", "/api/messages") => Response::json(201, sent()),
            _ => Response::json(200, json!({"sessions": [], "messages": [], "total": 0})),
        },
    )
}

fn registrations(requests: &[Request]) -> Vec<&Value> {
    requests
        .iter()
        .filter(|request| request.method == "POST" && request.path == "/api/sessions")
        .map(|request| &request.body)
        .collect()
}

fn claude(session: &str, profile: &'static str) -> Vec<(&'static str, String)> {
    vec![
        ("CLAUDECODE", "1".into()),
        ("CLAUDE_CODE_SESSION_ID", session.into()),
        ("HIBOSS_PROFILE", profile.into()),
    ]
}

fn env(pairs: &[(&'static str, String)]) -> Vec<(&'static str, &str)> {
    pairs
        .iter()
        .map(|(name, value)| (*name, value.as_str()))
        .collect()
}

#[test]
fn two_profiles_in_one_checkout_get_separate_state_directories() {
    let http = server();
    let mut fixture = Fixture::new("repo", &http.url);
    let claude_dir = fixture.prepare("claude-s1");
    let codex_dir = fixture.prepare("codex-s1");
    for profile in ["claude", "codex"] {
        let run = fixture.run(
            &fixture.repo,
            &["hook", "session-start"],
            &env(&claude("s1", profile)),
        );
        assert_eq!(run.code, 0, "{}", run.stderr);
        assert!(
            !run.stderr.contains("registration failed"),
            "{}",
            run.stderr
        );
    }
    let (claude_id, codex_id) = (
        read(&claude_dir.join("session")),
        read(&codex_dir.join("session")),
    );
    assert!(!claude_id.is_empty() && !codex_id.is_empty() && claude_id != codex_id);
    let requests = http.requests();
    let registered = registrations(&requests);
    assert_eq!(registered.len(), 2);
    assert_eq!(registered[0]["id"], claude_id.as_str());
    assert_eq!(registered[1]["id"], codex_id.as_str());
    assert_eq!(registered[0]["runtime"], "claude");
    assert!(
        registered[0]["host"]
            .as_str()
            .is_some_and(|host| !host.is_empty() && !host.contains('.'))
    );
    assert!(
        registered[0].get("dispatch_ref").is_none()
            && registered[0].get("parent_session_id").is_none()
    );
    let bearer = |index: usize| {
        requests
            .iter()
            .filter(|r| r.path == "/api/sessions" && r.method == "POST")
            .nth(index)
            .and_then(|r| r.header("authorization").map(str::to_owned))
    };
    assert_eq!(bearer(0).as_deref(), Some("Bearer synthetic-claude-key"));
    assert_eq!(bearer(1).as_deref(), Some("Bearer synthetic-codex-key"));
}

#[test]
fn worktree_shares_project_key_and_takes_project_identity_from_the_repository() {
    let http = server();
    let mut fixture = Fixture::new("alpha-repo", &http.url);
    let worktree = fixture.worktree("zzz-unrelated");
    let main_dir = fixture.prepare("claude-main");
    let tree_dir = fixture.prepare("claude-tree");
    let main = fixture.run(
        &fixture.repo,
        &["hook", "session-start"],
        &env(&claude("main", "claude")),
    );
    let tree = fixture.run(
        &worktree,
        &["hook", "session-start"],
        &env(&claude("tree", "claude")),
    );
    assert_eq!(
        (main.code, tree.code),
        (0, 0),
        "{}{}",
        main.stderr,
        tree.stderr
    );
    assert!(!read(&main_dir.join("session")).is_empty());
    assert!(
        !read(&tree_dir.join("session")).is_empty(),
        "worktree must use the main checkout's key"
    );
    let keys = std::fs::read_dir(fixture.root.join("tmp/hiboss"))
        .expect("state root")
        .count();
    assert_eq!(keys, 1, "one project_key for the checkout and its worktree");
    let requests = http.requests();
    let registered = registrations(&requests);
    assert_eq!(registered.len(), 2);
    for body in &registered {
        assert_eq!(body["project"], "alpha-repo");
        let aliases = body["project_identity"]["aliases"].to_string();
        assert!(!aliases.contains("zzz-unrelated"), "{aliases}");
    }
    assert_eq!(registered[1]["label"], "alpha-repo/zzz-unrelated");
    assert_eq!(
        registered[1]["cwd"]
            .as_str()
            .map(|cwd| cwd.ends_with("zzz-unrelated")),
        Some(true)
    );
}

#[test]
fn worktree_project_comes_from_the_remote_name() {
    let http = server();
    let mut fixture = Fixture::new("checkout", &http.url);
    fixture.git(
        &fixture.repo,
        &[
            "remote",
            "add",
            "origin",
            "git@example.test:org/Beta-Repo.git",
        ],
    );
    let worktree = fixture.worktree("feature-x");
    fixture.prepare("claude-s");
    let run = fixture.run(
        &worktree,
        &["hook", "session-start"],
        &env(&claude("s", "claude")),
    );
    assert_eq!(run.code, 0, "{}", run.stderr);
    let requests = http.requests();
    assert_eq!(registrations(&requests)[0]["project"], "beta-repo");
}

#[test]
fn hook_prints_session_registration_errors() {
    let http = Http::start(|request: &Request| match request.path.as_str() {
        "/api/sessions" if request.method == "POST" => Response::json(500, json!("boom")),
        _ => Response::json(200, json!({"sessions": [], "messages": [], "total": 0})),
    });
    let mut fixture = Fixture::new("repo", &http.url);
    fixture.prepare("claude-s");
    let run = fixture.run(
        &fixture.repo,
        &["hook", "session-start"],
        &env(&claude("s", "claude")),
    );
    assert_eq!(run.code, 0);
    assert!(
        run.stderr.contains("session registration failed"),
        "{}",
        run.stderr
    );
}

#[test]
fn foreign_session_is_replaced_and_the_send_retried_once() {
    let http = server();
    let mut fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude-s");
    std::fs::write(dir.join("session"), "foreign-session").expect("stale session");
    let run = fixture.run(
        &fixture.repo,
        &["send", "hello"],
        &env(&claude("s", "claude")),
    );
    assert_eq!(run.code, 0, "{}", run.stderr);
    let healed = run
        .stderr
        .lines()
        .filter(|line| line.contains("belonged to another agent"))
        .count();
    assert_eq!(healed, 1, "{}", run.stderr);
    let fresh = read(&dir.join("session"));
    assert!(!fresh.is_empty() && fresh != "foreign-session");
    let requests = http.requests();
    let sends: Vec<_> = requests
        .iter()
        .filter(|r| r.method == "POST" && r.path == "/api/messages")
        .collect();
    assert_eq!(sends.len(), 2, "one rejected send and one retry");
    assert_eq!(sends[1].body["session_id"], fresh.as_str());
    let registered = registrations(&requests);
    assert_eq!(registered.len(), 1);
    assert_eq!(registered[0]["id"], fresh.as_str());
}

#[test]
fn dispatched_mode_never_blocks_on_the_boss() {
    let http = server();
    let mut fixture = Fixture::new("repo", &http.url);
    fixture.prepare("claude-task-7");
    let aid = [
        ("AID_TASK_ID", "task-7"),
        ("CLAUDECODE", "1"),
        ("HIBOSS_PROFILE", "claude"),
    ];
    let start = fixture.run(&fixture.repo, &["hook", "session-start"], &aid);
    assert_eq!(start.code, 0, "{}", start.stderr);
    let stop = fixture.run(&fixture.repo, &["hook", "stop"], &aid);
    assert_eq!(stop.code, 0, "{}", stop.stderr);
    let ask = fixture.run(&fixture.repo, &["ask", "proceed?"], &aid);
    assert_eq!(ask.code, 4);
    assert_eq!(
        ask.stderr.trim(),
        "dispatched agents cannot ask the boss; return the question to your dispatcher"
    );
    let send = fixture.run(&fixture.repo, &["send", "status"], &aid);
    assert_eq!(send.code, 0, "{}", send.stderr);
    let requests = http.requests();
    assert!(
        requests.iter().all(|r| r.method != "PATCH"),
        "Stop must not park a dispatched session"
    );
    let registered = registrations(&requests);
    assert_eq!(
        (&registered[0]["runtime"], &registered[0]["dispatch_ref"]),
        (&json!("aid"), &json!("task-7"))
    );
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.method == "POST" && r.path == "/api/messages")
            .count(),
        1
    );
}
