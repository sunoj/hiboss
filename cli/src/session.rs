// Purpose: Read/write per-project session IDs for message isolation.
// Exports: session_file_path, read_session_id, write_session_id, project_hash.
// Dependencies: std::fs, std::env, std::sync::OnceLock.

use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

/// Cached project directory — resolved once per process via env var, git root, or cwd.
static PROJECT_DIR: OnceLock<String> = OnceLock::new();

fn resolve_project_dir() -> String {
    // 1. Env var override (set by hiboss setup hooks for reliable hook context)
    if let Ok(dir) = std::env::var("HIBOSS_PROJECT_DIR") {
        if !dir.is_empty() {
            return dir;
        }
    }
    // 2. Git repo root (deterministic regardless of subdirectory)
    if let Ok(output) = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let root = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !root.is_empty() {
                return root;
            }
        }
    }
    // 3. Fall back to cwd
    std::env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default()
}

/// Derive a short project hash for per-project session files.
/// Uses git root (cached) for deterministic results regardless of cwd.
pub fn project_hash() -> String {
    let dir = PROJECT_DIR.get_or_init(resolve_project_dir);
    fnv1a_hash(dir)
}

fn fnv1a_hash(s: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", h)
}

/// Path to the session file: /tmp/hiboss-session-<project_hash>
pub fn session_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-session-{}", project_hash()))
}

/// Path to per-session TTL file for urgent boss checks (5 min).
pub fn ttl_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-urgent-check-{}", project_hash()))
}

/// Path to per-session TTL file for agent-to-agent checks (30 sec).
pub fn a2a_ttl_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-a2a-check-{}", project_hash()))
}

/// Path to the daemon PID file for this project session.
pub fn daemon_pid_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-daemon-{}.pid", project_hash()))
}

/// Path to the daemon's pending messages file (JSON lines).
pub fn daemon_pending_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-daemon-{}.pending", project_hash()))
}

/// Path to the urgent message file (written by bg-check, read by post-tool-use).
pub fn urgent_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-urgent-{}", project_hash()))
}

/// Marker file: written by `hiboss ask`, checked by Stop hook.
pub fn asked_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-asked-{}", project_hash()))
}

/// Record that `hiboss ask` was called this session.
pub fn mark_asked() {
    let _ = fs::write(asked_marker_path(), "1");
}

/// Check whether `hiboss ask` was called this session.
pub fn has_asked() -> bool {
    asked_marker_path().exists()
}

/// Marker file: written by send/reply/react after an ask, checked by Stop hook.
pub fn replied_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-replied-{}", project_hash()))
}

/// Record that agent sent a reply/reaction after asking.
pub fn mark_replied() {
    if has_asked() {
        let _ = fs::write(replied_marker_path(), "1");
    }
}

/// Check whether agent replied after asking.
pub fn has_replied() -> bool {
    replied_marker_path().exists()
}

/// Check if the daemon is running by reading the PID file and testing the process.
pub fn is_daemon_running() -> Option<u32> {
    let pid_str = fs::read_to_string(daemon_pid_path()).ok()?;
    let pid: u32 = pid_str.trim().parse().ok()?;
    // Check if process is alive (signal 0 = test existence)
    let status = std::process::Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .ok()?;
    if status.success() { Some(pid) } else { None }
}

/// Read and clear pending messages from the daemon file. Returns JSON lines.
pub fn drain_pending_messages() -> Vec<String> {
    let path = daemon_pending_path();
    // Atomic read-and-truncate: rename then read
    let tmp = path.with_extension("draining");
    if fs::rename(&path, &tmp).is_err() {
        return vec![];
    }
    let content = fs::read_to_string(&tmp).unwrap_or_default();
    let _ = fs::remove_file(&tmp);
    content.lines().filter(|l| !l.is_empty()).map(|l| l.to_owned()).collect()
}

/// Read session_id from the session file, if it exists.
pub fn read_session_id() -> Option<String> {
    let path = session_file_path();
    fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
}

/// Write a new session_id to the session file.
pub fn write_session_id(id: &str) -> Result<(), std::io::Error> {
    fs::write(session_file_path(), id)
}
