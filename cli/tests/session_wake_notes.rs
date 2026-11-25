// Drives the built CLI, its real daemon and a stand-in for Claude Code's messaging socket:
// a boss note (留言) wakes an idle session once, never a busy one, and never with its text.
// Dependencies: session_identity_support (git sandbox + mock HTTP), session_wake_support.
#![cfg(unix)]

mod session_identity_support;
mod session_wake_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Response};
use session_identity_support::{Fixture, wait_until};
use session_wake_support::{Socket, claude, daemon_pid};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

type Pending = Arc<Mutex<Vec<&'static str>>>;

/// The notes endpoint serves whatever is pending; every stream stays quiet.
fn server(pending: Pending) -> Http {
    Http::start(move |request| {
        if request.path.contains("/notes?") {
            let notes: Vec<Value> = pending.lock().unwrap().iter().map(|id| json!({
                "id": id, "session_id": "s", "agent_id": "a", "boss_name": "boss",
                "body": "NOTE-TEXT-NOT-PUSHED", "status": "pending", "created_at": "2026-11-25 08:00:00",
                "read_at": null})).collect();
            return Response::json(200, json!({ "notes": notes }));
        }
        if request.path.starts_with("/api/messages/stream") {
            return Response::json(200, Value::String(": keepalive\n\n".into()));
        }
        Response::json(200, json!({"ok": true, "sessions": [], "messages": [], "total": 0}))
    })
}

/// The poll runs at most every 15 s; a test lifts that limit instead of waiting it out.
fn lift_poll_limit(dir: &Path) {
    let _ = std::fs::remove_file(dir.join("note-check"));
}

/// Waits past several daemon ticks, so a push that should not happen would have.
fn settle() {
    std::thread::sleep(Duration::from_secs(5));
}

fn idle_session(name: &str, pending: &Pending) -> (Http, Fixture, std::path::PathBuf, Socket) {
    let http = server(pending.clone());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind(name);
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    (http, fixture, dir, socket)
}

#[test]
fn a_note_wakes_an_idle_session_once_without_its_text() {
    let pending: Pending = Arc::default();
    let (_http, fixture, dir, socket) = idle_session("note-idle", &pending);
    claude(&fixture, &["hook", "stop"], Some(&socket));
    pending.lock().unwrap().push("note-0001");
    lift_poll_limit(&dir);
    assert!(wait_until(|| !socket.pushes().is_empty()), "the note did not wake the session");
    let pushes = socket.pushes();
    let content = pushes[0].lines().nth(1).map(|l| serde_json::from_str::<Value>(l).unwrap()).unwrap();
    let text = content["message"]["content"].as_str().unwrap();
    assert!(text.contains("1 new note") && text.contains("hiboss note read"), "{text}");
    assert!(!text.contains("NOTE-TEXT-NOT-PUSHED"), "{text}");

    // The woken turn ends without reading the note: it must not wake the session again.
    claude(&fixture, &["hook", "stop"], Some(&socket));
    lift_poll_limit(&dir);
    settle();
    assert_eq!(socket.pushes().len(), 1, "an unread note woke the session twice: {:?}", socket.pushes());

    // A second note does.
    pending.lock().unwrap().push("note-0002");
    lift_poll_limit(&dir);
    assert!(wait_until(|| socket.pushes().len() == 2), "{:?}", socket.pushes());
    assert!(socket.pushes()[1].contains("1 new note"), "{}", socket.pushes()[1]);
}

#[test]
fn a_note_left_while_the_session_works_wakes_it_only_after_the_turn_ends() {
    let pending: Pending = Arc::default();
    let (_http, fixture, dir, socket) = idle_session("note-busy", &pending);
    pending.lock().unwrap().push("note-busy-1");
    lift_poll_limit(&dir);
    settle();
    assert!(socket.pushes().is_empty(), "a working session was woken: {:?}", socket.pushes());
    claude(&fixture, &["hook", "stop"], Some(&socket));
    lift_poll_limit(&dir);
    assert!(wait_until(|| socket.pushes().len() == 1), "the note did not wake the session after Stop");
}

#[test]
fn a_note_read_before_the_turn_ends_does_not_wake_the_session() {
    let pending: Pending = Arc::default();
    let (http, fixture, dir, socket) = idle_session("note-read", &pending);
    // Left while the session works; the agent reads it (the server drops it from pending).
    pending.lock().unwrap().push("note-read-1");
    lift_poll_limit(&dir);
    settle();
    pending.lock().unwrap().clear();
    let polls = || http.paths().iter().filter(|p| p.contains("/notes?status=pending")).count();
    let before = polls();
    claude(&fixture, &["hook", "stop"], Some(&socket));
    lift_poll_limit(&dir);
    assert!(wait_until(|| polls() > before), "the idle daemon never polled after Stop");
    settle();
    assert!(socket.pushes().is_empty(), "{:?}", socket.pushes());
}
