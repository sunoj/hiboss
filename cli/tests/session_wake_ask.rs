// Drives `hiboss ask` against a mock server with a stand-in for Claude Code's messaging socket:
// the waiter delivers its reply like the daemon, so a detached ask still reaches an idle session.
// Dependencies: session_identity_support (git sandbox + mock HTTP), session_wake_support, serde_json.
#![cfg(unix)]

mod session_identity_support;
mod session_wake_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Response};
use session_identity_support::{Fixture, read, wait_until};
use session_wake_support::{Socket, claude, daemon_pid};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// A waiter detached with `&` or redirected to a file gets the reply, marks it read before the
/// stream sees it, and prints it where the agent never looks: the session must still learn of it.
fn ask_server(session: Arc<Mutex<String>>, auto_default: bool) -> Http {
    gated_ask_server(session, auto_default, Arc::new(AtomicBool::new(true)))
}

/// Serves one ask whose poll returns, once `released`, a decision reply addressed to the
/// session in `session`; before that each poll returns the ask without a reply.
fn gated_ask_server(session: Arc<Mutex<String>>, auto_default: bool, released: Arc<AtomicBool>) -> Http {
    let source = if auto_default { "system" } else { "api" };
    let status = if auto_default { "not_applicable" } else { "not_configured" };
    Http::start(move |request| {
        if request.path.contains("/poll?") && !released.load(Ordering::SeqCst) {
            return Response::json(200, json!({"id": "ask-1", "direction": "agent_to_boss", "replies": []}));
        }
        if request.path.contains("/poll?") {
            let mut metadata = json!({"source": source, "provenance":
                {"version": 1, "source": source, "signature": {"status": status}}});
            if auto_default {
                metadata["auto_default"] = json!(true);
            }
            let reply = json!({"id": "reply-spooled", "direction": "boss_to_agent", "reply_to": "ask-1",
                "target_session_id": *session.lock().unwrap(), "body": "BODY-FROM-ASK", "metadata": metadata});
            return Response::json(200, json!({"id": "ask-1", "direction": "agent_to_boss", "replies": [reply]}));
        }
        match (request.method.as_str(), request.path.as_str()) {
            ("POST", "/api/messages") => Response::json(201,
                json!({"id": "ask-1", "status": "sent", "created_at": "2026-11-24T00:00:00Z"})),
            ("GET", path) if path.starts_with("/api/messages/stream") => {
                Response::json(200, Value::String(": keepalive\n\n".into()))
            }
            _ => Response::json(200, json!({"ok": true, "sessions": [], "messages": [], "total": 0})),
        }
    })
}

#[test]
fn a_reply_taken_by_a_detached_ask_wakes_the_session_at_stop() {
    let session: Arc<Mutex<String>> = Arc::default();
    let http = ask_server(session.clone(), false);
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("ask");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    *session.lock().unwrap() = read(&dir.join("session"));
    let ask = claude(&fixture, &["ask", "Deploy?", "--option", "Yes", "--option", "No", "--timeout", "60"], Some(&socket));
    assert!(ask.stdout.contains("BODY-FROM-ASK"), "the waiter still returns the reply: {}", ask.stdout);
    assert!(socket.pushes().is_empty(), "a working session is not pushed");
    claude(&fixture, &["hook", "stop"], Some(&socket));
    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 1, "{pushes:?}");
    assert!(pushes[0].contains("reply-spooled") && pushes[0].contains("ask-1"), "{}", pushes[0]);
    assert!(!pushes[0].contains("BODY-FROM-ASK"), "{}", pushes[0]);
    let hook = claude(&fixture, &["hook", "post-tool-use"], Some(&socket));
    assert_eq!(hook.stdout.matches("BODY-FROM-ASK").count(), 1, "{}", hook.stdout);
}

#[test]
fn a_server_default_never_reaches_the_agent_as_the_bosss_answer() {
    let session: Arc<Mutex<String>> = Arc::default();
    let http = ask_server(session.clone(), true);
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("default");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    *session.lock().unwrap() = read(&dir.join("session"));
    claude(&fixture, &["ask", "Deploy?", "--option", "Yes", "--option", "No", "--timeout", "60"], Some(&socket));
    claude(&fixture, &["hook", "stop"], Some(&socket));
    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 1, "{pushes:?}");
    assert!(pushes[0].contains("not a boss decision"), "{}", pushes[0]);
    let hook = claude(&fixture, &["hook", "post-tool-use"], Some(&socket));
    assert!(hook.stdout.contains("[server default]") && hook.stdout.contains("not a boss decision"), "{}", hook.stdout);
    assert!(!hook.stdout.contains("[boss]"), "{}", hook.stdout);
}

/// The usual timing of a detached ask: the turn ends first, and the reply arrives while the
/// session is idle. The waiter must wake it itself; the next Stop is not coming.
#[test]
fn a_reply_after_the_turn_ended_wakes_the_session_through_a_detached_ask() {
    let session: Arc<Mutex<String>> = Arc::default();
    let released = Arc::new(AtomicBool::new(false));
    let http = gated_ask_server(session.clone(), false, released.clone());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("late");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    *session.lock().unwrap() = read(&dir.join("session"));
    let mut ask = Command::new(env!("CARGO_BIN_EXE_hiboss"))
        .args(["ask", "Deploy?", "--option", "Yes", "--option", "No", "--timeout", "60"])
        .current_dir(&fixture.repo)
        .env_clear()
        .env("HOME", &fixture.root)
        .env("HIBOSS_CONFIG", fixture.config())
        .env("PATH", "/usr/bin:/bin")
        .env("NO_PROXY", "127.0.0.1")
        .envs([("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s"), ("HIBOSS_PROFILE", "claude"),
            ("CLAUDE_CODE_MESSAGING_TOKEN", "tok")])
        .env("CLAUDE_CODE_MESSAGING_SOCKET", &socket.path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn ask");
    assert!(wait_until(|| http.paths().iter().any(|p| p.contains("/poll?"))), "the ask never polled");
    claude(&fixture, &["hook", "stop"], Some(&socket));
    assert!(socket.pushes().is_empty(), "nothing to wake for yet");
    released.store(true, Ordering::SeqCst);
    assert!(wait_until(|| !socket.pushes().is_empty()), "the reply never woke the idle session");
    let status = ask.wait().expect("ask exits");
    assert!(status.success());
    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 1, "{pushes:?}");
    assert!(pushes[0].contains("reply-spooled") && !pushes[0].contains("BODY-FROM-ASK"), "{}", pushes[0]);
}
