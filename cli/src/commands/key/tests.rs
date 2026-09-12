// Rotation tests with a real loopback mock server and isolated config files.
// Covers success, verification/revocation failures and atomic persistence without new crates.
use super::*;
use std::{fs, io::{Read, Write}, net::TcpListener, path::PathBuf, thread};

struct Mock {
    server: String, path: PathBuf, requests: thread::JoinHandle<()>,
}
struct Reply { method: &'static str, path: &'static str, bearer: &'static str, status: u16, body: &'static str }
const OLD: &str = r#"{"id":"agent","agent_key_id":"old-id"}"#;
const NEW: &str = r#"{"id":"agent","agent_key_id":"new-id"}"#;
fn reply(method: &'static str, path: &'static str, bearer: &'static str, status: u16, body: &'static str) -> Reply {
    Reply { method, path, bearer, status, body }
}
fn prepare(replies: Vec<Reply>) -> Mock {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let server = format!("http://{}", listener.local_addr().unwrap());
    let root = std::env::temp_dir().join(format!("hiboss-key-{}-{}", std::process::id(), listener.local_addr().unwrap().port()));
    fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    fs::write(&path, serde_json::json!({ "server": server, "key": "old-key", "channel": "api", "future": 42 }).to_string()).unwrap();
    let config_path = path.clone();
    let requests = thread::spawn(move || {
        for response in replies { serve(&listener, response, &config_path); }
    });
    Mock { server, path, requests }
}
fn serve(listener: &TcpListener, reply: Reply, path: &Path) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    let mut socket = loop {
        if let Ok((socket, _)) = listener.accept() { break socket; }
        assert!(std::time::Instant::now() < deadline, "expected {} {}", reply.method, reply.path);
        thread::sleep(std::time::Duration::from_millis(10));
    };
    socket.set_nonblocking(false).unwrap();
    socket.set_read_timeout(Some(std::time::Duration::from_secs(5))).unwrap();
    let mut bytes = Vec::new();
    let mut byte = [0; 1];
    while !bytes.ends_with(b"\r\n\r\n") { socket.read_exact(&mut byte).unwrap(); bytes.push(byte[0]); }
    let request = String::from_utf8(bytes).unwrap();
    let length = request.lines().find_map(|line| line.to_lowercase().strip_prefix("content-length: ")
        .and_then(|value| value.parse::<usize>().ok())).unwrap_or(0);
    let mut body = vec![0; length];
    socket.read_exact(&mut body).unwrap();
    assert!(request.starts_with(&format!("{} /api/agents/me{} HTTP/1.1", reply.method, reply.path)));
    assert!(request.to_lowercase().contains(&format!("authorization: bearer {}", reply.bearer)));
    if reply.method == "DELETE" {
        let config: serde_json::Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
        assert_eq!(config["key"], "new-key", "config must be installed before revocation");
    }
    write!(socket, "HTTP/1.1 {} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        reply.status, reply.body.len(), reply.body).unwrap();
}
fn beginning() -> Vec<Reply> {
    vec![reply("GET", "", "old-key", 200, OLD),
        reply("POST", "/keys", "old-key", 201, r#"{"id":"new-id","key":"new-key"}"#)]
}
impl Mock {
    fn config(&self) -> Config { Config { server: Some(self.server.clone()), key: Some("old-key".into()), channel: Some("api".into()) } }
    fn stored(&self) -> serde_json::Value { serde_json::from_slice(&fs::read(&self.path).unwrap()).unwrap() }
    fn finish(self) { self.requests.join().unwrap(); fs::remove_dir_all(self.path.parent().unwrap()).unwrap(); }
}

#[tokio::test]
async fn rotates_after_verification_and_preserves_other_config_fields() {
    let mut replies = beginning();
    replies.extend([reply("GET", "", "new-key", 200, NEW), reply("DELETE", "/keys/old-id", "new-key", 200, "{}")]);
    let mock = prepare(replies);
    assert_eq!(rotate(&mock.config(), &mock.path, "Mac").await.unwrap(), "new-id");
    assert_eq!(mock.stored()["key"], "new-key");
    assert_eq!(mock.stored()["future"], 42);
    assert!(!mock.path.with_extension("key-previous").exists());
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; assert_eq!(fs::metadata(&mock.path).unwrap().permissions().mode() & 0o777, 0o600); }
    mock.finish();
}

#[tokio::test]
async fn verification_failure_keeps_old_config_and_never_revokes_it() {
    let mut replies = beginning();
    replies.push(reply("GET", "", "new-key", 401, "{}"));
    let mock = prepare(replies);
    let original = fs::read(&mock.path).unwrap();
    let error = rotate(&mock.config(), &mock.path, "Mac").await.unwrap_err().to_string();
    assert!(error.contains("previous key retained"));
    assert_eq!(fs::read(&mock.path).unwrap(), original);
    assert_eq!(fs::read(mock.path.with_extension("key-previous")).unwrap(), original);
    mock.finish();
}

#[tokio::test]
async fn revocation_failure_restores_live_old_key_atomically() {
    let mut replies = beginning();
    replies.extend([reply("GET", "", "new-key", 200, NEW), reply("DELETE", "/keys/old-id", "new-key", 503, "{}"), reply("GET", "", "old-key", 200, OLD)]);
    let mock = prepare(replies);
    let original = fs::read(&mock.path).unwrap();
    let error = rotate(&mock.config(), &mock.path, "Mac").await.unwrap_err().to_string();
    assert!(error.contains("restored the previous active key"));
    assert_eq!(fs::read(&mock.path).unwrap(), original);
    mock.finish();
}

#[tokio::test]
async fn uncertain_revoke_keeps_verified_new_config_and_old_recovery_backup() {
    let mut replies = beginning();
    replies.extend([reply("GET", "", "new-key", 200, NEW), reply("DELETE", "/keys/old-id", "new-key", 503, "{}"), reply("GET", "", "old-key", 401, "{}")]);
    let mock = prepare(replies);
    let error = rotate(&mock.config(), &mock.path, "Mac").await.unwrap_err().to_string();
    assert!(error.contains("outcome uncertain"));
    assert_eq!(mock.stored()["key"], "new-key");
    let saved: serde_json::Value = serde_json::from_slice(&fs::read(mock.path.with_extension("key-previous")).unwrap()).unwrap();
    assert_eq!(saved["key"], "old-key");
    mock.finish();
}

#[tokio::test]
async fn install_failure_does_not_revoke_old_key() {
    let mut replies = beginning();
    replies.push(reply("GET", "", "new-key", 200, NEW));
    let mock = prepare(replies);
    fs::write(mock.path.with_extension("key-next"), "occupied").unwrap();
    assert!(rotate(&mock.config(), &mock.path, "Mac").await.is_err());
    assert_eq!(mock.stored()["key"], "old-key");
    mock.finish();
}

#[tokio::test]
async fn mint_failure_keeps_previous_key() {
    let mock = prepare(vec![reply("GET", "", "old-key", 200, OLD), reply("POST", "/keys", "old-key", 500, "{}")]);
    assert!(rotate(&mock.config(), &mock.path, "Mac").await.unwrap_err().to_string().contains("previous key retained"));
    assert_eq!(mock.stored()["key"], "old-key");
    mock.finish();
}

#[tokio::test]
async fn verification_rejects_another_identity_without_changing_config() {
    let mut replies = beginning();
    replies.push(reply("GET", "", "new-key", 200, r#"{"id":"other","agent_key_id":"new-id"}"#));
    let mock = prepare(replies);
    assert!(rotate(&mock.config(), &mock.path, "Mac").await.unwrap_err().to_string().contains("did not match"));
    assert_eq!(mock.stored()["key"], "old-key");
    mock.finish();
}
