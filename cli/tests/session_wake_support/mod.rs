// Shared helpers for the session wake e2e tests: a stand-in for Claude Code's messaging socket,
// hook runs carrying that socket, and the daemon pid. Dependencies: session_identity_support.
#![allow(dead_code)]

use super::session_identity_support::{Fixture, Run, read, wait_until};
use std::io::Read;
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

/// A stand-in for Claude Code's socket: records every non-empty write (probes write nothing).
pub struct Socket {
    pub path: PathBuf,
    pushes: Arc<Mutex<Vec<String>>>,
}

impl Socket {
    pub fn bind(name: &str) -> Self {
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

    pub fn pushes(&self) -> Vec<String> {
        self.pushes.lock().unwrap().clone()
    }
}

impl Drop for Socket {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub fn claude(fixture: &Fixture, args: &[&str], socket: Option<&Socket>) -> Run {
    let path = socket.map(|s| s.path.to_string_lossy().into_owned());
    let mut env = vec![("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s"), ("HIBOSS_PROFILE", "claude")];
    if let Some(path) = path.as_deref() {
        env.extend([("CLAUDE_CODE_MESSAGING_SOCKET", path), ("CLAUDE_CODE_MESSAGING_TOKEN", "tok")]);
    }
    let run = fixture.run(&fixture.repo, args, &env);
    assert_eq!(run.code, 0, "{args:?}: {}", run.stderr);
    run
}

pub fn daemon_pid(dir: &std::path::Path) -> u32 {
    assert!(wait_until(|| dir.join("daemon.pid").exists()), "no daemon pid");
    read(&dir.join("daemon.pid")).parse().expect("daemon pid")
}

