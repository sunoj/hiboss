// Drives the built CLI, its real daemon and a stand-in for Claude Code's messaging socket:
// an idle session is woken once by a boss reply addressed to it, and never with its body.
// Dependencies: session_identity_support (git sandbox + mock HTTP), serde_json, Unix sockets.
#![cfg(unix)]

mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Response};
use session_identity_support::{Fixture, Run, is_hiboss, read, wait_until};
use std::io::Read;
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

type Queue = Arc<Mutex<Vec<String>>>;

/// Each stream GET serves the next queued SSE body, or a keepalive as a quiet live stream does.
fn server(queue: Queue) -> Http {
    serve(queue, ": keepalive\n\n")
}

/// `idle` is what a stream GET returns when nothing is queued.
fn serve(queue: Queue, idle: &'static str) -> Http {
    Http::start(move |request| match (request.method.as_str(), request.path.as_str()) {
        ("GET", path) if path.starts_with("/api/messages/stream") => {
            let next = queue.lock().unwrap().pop();
            Response::json(200, Value::String(next.unwrap_or_else(|| idle.into())))
        }
        _ => Response::json(200, json!({"ok": true, "sessions": [], "messages": [], "total": 0})),
    })
}

fn sse(messages: &[Value]) -> String {
    messages.iter().map(|m| format!("event: message\ndata: {m}\n\n")).collect()
}

fn reply(id: &str, target: &str) -> Value {
    json!({"id": id, "direction": "boss_to_agent", "target_session_id": target,
        "reply_to": "msg-ask-0001", "agent_name": "boss", "body": "BODY-NOT-PUSHED", "metadata": {}})
}

/// A stand-in for Claude Code's socket: records every non-empty write (probes write nothing).
struct Socket {
    path: PathBuf,
    pushes: Arc<Mutex<Vec<String>>>,
}

impl Socket {
    fn bind(name: &str) -> Self {
        let path = PathBuf::from(format!("/tmp/hbw-{}-{name}.sock", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path).unwrap();
        let pushes: Arc<Mutex<Vec<String>>> = Arc::default();
        let log = pushes.clone();
        std::thread::spawn(move || {
            for mut stream in listener.incoming().flatten() {
                let mut text = String::new();
                let _ = stream.read_to_string(&mut text);
                if !text.is_empty() {
                    log.lock().unwrap().push(text);
                }
            }
        });
        Self { path, pushes }
    }

    fn pushes(&self) -> Vec<String> {
        self.pushes.lock().unwrap().clone()
    }
}

impl Drop for Socket {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn claude(fixture: &Fixture, args: &[&str], socket: Option<&Socket>) -> Run {
    let path = socket.map(|s| s.path.to_string_lossy().into_owned());
    let mut env = vec![("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s"), ("HIBOSS_PROFILE", "claude")];
    if let Some(path) = path.as_deref() {
        env.extend([("CLAUDE_CODE_MESSAGING_SOCKET", path), ("CLAUDE_CODE_MESSAGING_TOKEN", "tok")]);
    }
    let run = fixture.run(&fixture.repo, args, &env);
    assert_eq!(run.code, 0, "{args:?}: {}", run.stderr);
    run
}

fn daemon_pid(dir: &std::path::Path) -> u32 {
    assert!(wait_until(|| dir.join("daemon.pid").exists()), "no daemon pid");
    read(&dir.join("daemon.pid")).parse().expect("daemon pid")
}

/// Lets the daemon run several more reconnects so a second push would have arrived.
fn settle(queue: &Queue) {
    assert!(wait_until(|| queue.lock().unwrap().is_empty()), "the stream was not read");
    std::thread::sleep(Duration::from_millis(1500));
}

#[test]
fn an_idle_session_is_woken_once_by_a_reply_addressed_to_it() {
    let queue: Queue = Arc::default();
    let http = server(queue.clone());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("idle");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    let daemon = daemon_pid(&dir);
    claude(&fixture, &["hook", "stop"], Some(&socket));
    assert_eq!(daemon_pid(&dir), daemon, "Stop keeps the daemon of a session it can wake");
    assert!(is_hiboss(daemon));
    let session = read(&dir.join("session"));
    let mut peer = reply("msg-peer-0001", &session);
    peer["direction"] = json!("agent_to_agent");
    let messages = [reply("msg-other-001", "other-session"), peer,
        reply("msg-reply-001", &session), reply("msg-reply-002", &session)];
    queue.lock().unwrap().push(sse(&messages));
    settle(&queue);

    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 1, "one push per idle period: {pushes:?}");
    let lines: Vec<Value> = pushes[0].lines().map(|l| serde_json::from_str(l).unwrap()).collect();
    assert_eq!(lines[0], json!({"type": "auth", "token": "tok"}));
    let content = lines[1]["message"]["content"].as_str().unwrap();
    assert!(content.contains("msg-reply-001") && content.contains("hiboss status msg-ask-0001"), "{content}");
    assert!(!content.contains("BODY-NOT-PUSHED"), "{content}");
    // The bodies still reach the agent through the hook, as labelled messages.
    let hook = claude(&fixture, &["hook", "post-tool-use"], Some(&socket));
    assert!(hook.stdout.contains("BODY-NOT-PUSHED"), "{}", hook.stdout);
}

#[test]
fn a_woken_turn_without_a_tool_call_is_not_woken_again_for_the_same_reply() {
    let queue: Queue = Arc::default();
    let http = server(queue.clone());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("loop");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    claude(&fixture, &["hook", "stop"], Some(&socket));
    let session = read(&dir.join("session"));
    queue.lock().unwrap().push(sse(&[reply("msg-reply-loop", &session)]));
    settle(&queue);
    assert_eq!(socket.pushes().len(), 1);
    // The woken turn only answers in text: no PostToolUse drains the spool before each Stop.
    claude(&fixture, &["hook", "stop"], Some(&socket));
    claude(&fixture, &["hook", "stop"], Some(&socket));
    assert_eq!(socket.pushes().len(), 1, "the same reply woke the session again: {:?}", socket.pushes());
    // A new reply after the turn ends still wakes it.
    queue.lock().unwrap().push(sse(&[reply("msg-reply-next", &session)]));
    settle(&queue);
    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 2, "{pushes:?}");
    assert!(pushes[1].contains("msg-reply-next"), "{}", pushes[1]);
}

#[test]
fn a_stream_that_ends_without_data_backs_off() {
    let http = serve(Queue::default(), "");
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("empty");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    std::thread::sleep(Duration::from_secs(3));
    let streams = http.paths().iter().filter(|p| p.starts_with("GET /api/messages/stream")).count();
    assert!((1..=2).contains(&streams), "reconnected {streams} times in 3s");
    assert!(read(&dir.join("daemon.log")).contains("ended without data"));
}

#[test]
fn a_reply_spooled_during_the_turn_wakes_the_session_at_stop() {
    let queue: Queue = Arc::default();
    let http = server(queue.clone());
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let socket = Socket::bind("busy");
    claude(&fixture, &["hook", "session-start"], Some(&socket));
    daemon_pid(&dir);
    let session = read(&dir.join("session"));
    queue.lock().unwrap().push(sse(&[reply("msg-reply-busy", &session)]));
    settle(&queue);
    assert!(socket.pushes().is_empty(), "a working session is not pushed");
    claude(&fixture, &["hook", "stop"], Some(&socket));
    let pushes = socket.pushes();
    assert_eq!(pushes.len(), 1, "{pushes:?}");
    assert!(pushes[0].contains("msg-reply-busy"), "{}", pushes[0]);
}

#[test]
fn a_new_socket_replaces_the_daemon_and_a_gone_socket_ends_it() {
    let queue: Queue = Arc::default();
    let http = server(queue);
    let fixture = Fixture::new("repo", &http.url);
    let dir = fixture.prepare("claude", "s");
    let first = Socket::bind("first");
    claude(&fixture, &["hook", "session-start"], Some(&first));
    let old = daemon_pid(&dir);
    // A resumed session keeps its state directory but gets a new Claude Code socket.
    let second = Socket::bind("second");
    claude(&fixture, &["hook", "session-start"], Some(&second));
    let new = daemon_pid(&dir);
    assert_ne!(old, new, "the daemon follows the new socket");
    assert!(wait_until(|| !is_hiboss(old)), "the old daemon was stopped");
    assert_eq!(read(&dir.join("daemon.socket")), second.path.to_string_lossy());
    drop(second);
    assert!(wait_until(|| !is_hiboss(new)), "the daemon exits once its session is gone");
    assert!(!dir.join("daemon.pid").exists());
}
