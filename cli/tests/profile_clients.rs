// Verifies each credential rule sends its selected bearer to the selected server.
// Runs the built CLI against synthetic loopback HTTP servers and isolated HOME/config.
// Dependencies: std networking/process APIs and serde_json; no external services.

use serde_json::json;
use std::{
    fs,
    io::{Read, Write},
    net::TcpListener,
    path::PathBuf,
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
    thread,
    time::{Duration, Instant},
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Sandbox(PathBuf);

impl Sandbox {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "hiboss-client-profile-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).expect("fixture directory");
        Self(root)
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn serve(listener: TcpListener) -> String {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut socket = loop {
        if let Ok((socket, _)) = listener.accept() {
            break socket;
        }
        assert!(
            Instant::now() < deadline,
            "CLI must contact the selected server"
        );
        thread::sleep(Duration::from_millis(10));
    };
    socket
        .set_read_timeout(Some(Duration::from_secs(3)))
        .expect("read deadline");
    let mut request = Vec::new();
    let mut byte = [0; 1];
    while !request.ends_with(b"\r\n\r\n") {
        socket.read_exact(&mut byte).expect("request header");
        request.push(byte[0]);
    }
    let body =
        r#"{"id":"msg_1","direction":"agent_to_boss","status":"sent","metadata":{},"replies":[]}"#;
    write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).expect("response");
    String::from_utf8(request).expect("HTTP text")
}

fn run_case(env: &[(&str, &str)], expected_profile: &str, ephemeral: bool) {
    let sandbox = Sandbox::new();
    let listener = TcpListener::bind("127.0.0.1:0").expect("synthetic server");
    listener.set_nonblocking(true).expect("nonblocking accept");
    let server = format!("http://{}", listener.local_addr().expect("address"));
    let key = format!("synthetic-{expected_profile}-bearer");
    let path = sandbox.0.join("config.json");
    if !ephemeral {
        let config = json!({"version":2,"server":"http://127.0.0.1:9","default_profile":"default",
            "profiles": {expected_profile: {"server":server,"key":key}}});
        fs::write(&path, config.to_string()).expect("synthetic config");
    }
    let receiver = thread::spawn(move || serve(listener));
    let mut command = Command::new(env!("CARGO_BIN_EXE_hiboss"));
    command
        .env_clear()
        .current_dir(&sandbox.0)
        .env("HOME", &sandbox.0)
        .env("HIBOSS_CONFIG", &path)
        .envs(env.iter().copied());
    if ephemeral {
        command
            .env("HIBOSS_SERVER", &server)
            .env("HIBOSS_KEY", &key);
    }
    let output = command
        .args(["status", "msg_1", "--json"])
        .output()
        .expect("run CLI");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let request = receiver.join().expect("server finished");
    assert!(request.starts_with("GET /api/messages/msg_1 HTTP/1.1"));
    assert!(
        request
            .to_lowercase()
            .contains(&format!("authorization: bearer {key}"))
    );
    assert_eq!(path.exists(), !ephemeral);
}

#[test]
fn real_requests_use_the_same_credentials_as_whoami_for_rules_one_through_four() {
    run_case(
        &[("HIBOSS_PROFILE", "missing"), ("AID_TASK_ID", "task")],
        "environment",
        true,
    );
    run_case(
        &[("HIBOSS_PROFILE", "claude"), ("AID_TASK_ID", "task")],
        "claude",
        false,
    );
    run_case(
        &[("AID_TASK_ID", "task"), ("CLAUDECODE", "1")],
        "aid",
        false,
    );
    run_case(&[("CLAUDECODE", "1")], "claude", false);
    run_case(&[], "default", false);
}
