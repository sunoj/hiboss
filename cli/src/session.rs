// Purpose: Read/write per-session IDs, daemon files and markers in the session state directory.
// Exports: read_session_id, write_session_id, daemon pid/spool helpers, state I/O, resolve_project.
// Dependencies: std::fs, std::env, std::sync::OnceLock.

mod markers;
mod private;
mod project;
mod state;
pub use markers::*;
pub use private::{append_state, open_log, read_state, remove_state, state_file, take_state, write_state};
pub use project::{ProjectIdentity, resolve_project};
pub use state::{git_common_dir, project_key, short_host, state_dir};
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

/// Return the resolved project directory path (git root, env override, or cwd).
pub fn project_dir() -> String {
    PROJECT_DIR.get_or_init(resolve_project_dir).clone()
}

/// Return the canonical project slug used by sessions and progress.
pub fn project_name() -> String {
    resolve_project(None).slug
}

fn fnv1a_hash(s: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", h)
}

pub const SESSION: &str = "session";
/// TTL for urgent boss checks (5 min) and agent-to-agent checks (30 sec).
pub const URGENT_CHECK: &str = "urgent-check";
pub const A2A_CHECK: &str = "a2a-check";
pub const DAEMON_PID: &str = "daemon.pid";
pub const DAEMON_PENDING: &str = "daemon.pending";
pub const DAEMON_LOG: &str = "daemon.log";
/// Urgent notice written by bg-check and printed by post-tool-use.
pub const URGENT: &str = "urgent";

/// Check if the daemon is running by reading the PID file and testing the process.
pub fn is_daemon_running() -> Option<u32> {
    let pid: u32 = read_state(DAEMON_PID)?.trim().parse().ok()?;
    // Check if process is alive (signal 0 = test existence)
    let status = std::process::Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .ok()?;
    if status.success() { Some(pid) } else { None }
}

/// Read and clear pending messages from the daemon spool. Returns JSON lines.
/// These lines are injected into the agent context as trusted [boss]/[peer] messages,
/// so only a spool that passes the private-file check is drained.
pub fn drain_pending_messages() -> Vec<String> {
    take_state(DAEMON_PENDING)
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_owned())
        .collect()
}

/// Read session_id from the session file, if it exists.
pub fn read_session_id() -> Option<String> {
    read_state(SESSION)
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
}

/// Write a new session_id to the session file.
pub fn write_session_id(id: &str) -> Result<(), std::io::Error> {
    write_state(SESSION, id)
}

fn panel_epoch_name(panel_id: &str) -> String {
    format!("panel-{panel_id}-epoch")
}

/// Read the epoch last claimed by this session for one panel.
pub fn read_panel_epoch(panel_id: &str) -> Option<String> {
    read_state(&panel_epoch_name(panel_id))
        .map(|body| body.trim().to_owned())
        .filter(|body| !body.is_empty())
}

/// Record or clear a panel epoch in the session state directory.
pub fn write_panel_epoch(panel_id: &str, epoch: Option<&str>) -> Result<(), Box<dyn std::error::Error>> {
    match epoch {
        Some(epoch) => write_state(&panel_epoch_name(panel_id), epoch)?,
        None => remove_state(&panel_epoch_name(panel_id)),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn project_name_non_empty() {
        assert!(!project_name().is_empty());
    }

    #[test]
    fn project_name_has_no_separator() {
        let name = project_name();
        assert!(!name.contains('/'));
        assert!(!name.contains('\\'));
    }

    #[test]
    fn panel_epoch_round_trip_is_session_local() {
        let panel_id = format!("session-test-{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).expect("clock").as_nanos());
        write_panel_epoch(&panel_id, Some("epoch-test")).expect("write epoch");
        assert_eq!(read_panel_epoch(&panel_id).as_deref(), Some("epoch-test"));
        write_panel_epoch(&panel_id, None).expect("clear epoch");
        assert_eq!(read_panel_epoch(&panel_id), None);
    }
}
