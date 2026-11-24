// Unit tests for the session wake: which messages wake a session, the notice's fixed fields,
// and the two-line auth/user frame written to a stand-in for Claude Code's messaging socket.
use super::*;
use serde_json::json;
use std::io::Read;
use std::os::unix::net::UnixListener;

const SESSION: &str = "sess-1";

fn reply(target: &str) -> Value {
    json!({"id": "msg-reply-1", "direction": "boss_to_agent", "target_session_id": target,
        "reply_to": "msg-ask-1", "body": "SECRET-BODY", "metadata": {}})
}

#[test]
fn only_a_boss_message_for_exactly_this_session_wakes_it() {
    assert!(notice_for(&reply(SESSION), Some(SESSION)).is_some());
    assert!(notice_for(&reply("other"), Some(SESSION)).is_none(), "another session's reply");
    assert!(notice_for(&json!({"id": "m", "direction": "boss_to_agent", "target_session_id": null}),
        Some(SESSION)).is_none(), "an untargeted boss message");
    let mut peer = reply(SESSION);
    peer["direction"] = json!("agent_to_agent");
    assert!(notice_for(&peer, Some(SESSION)).is_none(), "a peer message");
    assert!(notice_for(&reply(SESSION), None).is_none(), "no session id");
    assert!(notice_for(&reply(""), Some("")).is_none(), "an empty session id");
}

#[test]
fn notice_carries_ids_and_commands_never_the_body() {
    let text = notice_for(&reply(SESSION), Some(SESSION)).unwrap();
    assert!(text.contains("msg-ask-1") && text.contains("msg-reply-1"), "{text}");
    assert!(text.contains("hiboss status msg-ask-1"), "{text}");
    assert!(!text.contains("SECRET-BODY"), "{text}");
}

#[test]
fn an_auto_default_is_not_presented_as_a_boss_decision() {
    let mut message = reply(SESSION);
    message["metadata"] = json!({"auto_default": true});
    let text = notice_for(&message, Some(SESSION)).unwrap();
    assert!(text.contains("not a boss decision"), "{text}");
    assert!(!text.contains("The boss replied"), "{text}");
}

#[test]
fn an_unusual_id_is_never_interpolated() {
    let mut message = reply(SESSION);
    message["id"] = json!("x`; rm -rf ~`");
    assert!(notice_for(&message, Some(SESSION)).is_none());
    message["id"] = json!("msg-reply-1");
    message["reply_to"] = json!("bad id");
    let text = notice_for(&message, Some(SESSION)).unwrap();
    assert!(!text.contains("bad id") && text.contains("hiboss inbox"), "{text}");
}

#[tokio::test]
async fn push_writes_auth_then_one_user_turn_and_probe_tells_gone() {
    // A short path: Unix socket paths are limited to about 104 bytes.
    let socket = PathBuf::from(format!("/tmp/hiboss-wake-{}.sock", std::process::id()));
    let _ = std::fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket).unwrap();
    let reader = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut text = String::new();
        stream.read_to_string(&mut text).unwrap();
        text
    });
    let inbox = Inbox::new(socket.clone(), "tok");
    inbox.push("hello".into()).await.unwrap();
    let text = reader.join().unwrap();
    let lines: Vec<Value> = text.lines().map(|line| serde_json::from_str(line).unwrap()).collect();
    assert_eq!(lines.len(), 2, "{text}");
    assert_eq!(lines[0], json!({"type": "auth", "token": "tok"}));
    assert_eq!(lines[1]["type"], "user");
    assert_eq!(lines[1]["message"], json!({"role": "user", "content": "hello"}));
    // The listener is closed and the file left behind, as after a Claude Code crash.
    assert_eq!(inbox.probe(), Probe::Gone);
    std::fs::remove_file(&socket).unwrap();
    assert_eq!(inbox.probe(), Probe::Gone);
    assert!(inbox.push("again".into()).await.is_err_and(|err| is_gone(&err)));
}
