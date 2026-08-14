// Purpose: Read/write per-project session IDs for message isolation.
// Exports: session_file_path, read_session_id, write_session_id, project_hash.
// Dependencies: std::fs, std::env, std::sync::OnceLock.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// Write a file owner-only (0600), refusing to follow a symlink planted at the
/// (predictable) /tmp path. On multi-user hosts a co-resident user could otherwise
/// pre-create these paths as symlinks to redirect the write, or leave them
/// world-readable. `O_NOFOLLOW` makes open() fail if the final component is a
/// symlink; the 0600 mode + owner check on read close the confidentiality and
/// injection surface. Falls back to a plain write on non-unix platforms.
pub fn write_private(path: &Path, content: &str) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(path)?;
        file.write_all(content.as_bytes())?;
        Ok(())
    }
    #[cfg(not(unix))]
    {
        fs::write(path, content)
    }
}

/// True only if `path` is a regular file we exclusively own (not a symlink, owned
/// by the current euid, no group/other permission bits). Used to refuse injecting
/// content from a /tmp file a co-resident user may have planted or tampered with.
/// Non-unix: best-effort true (no shared-/tmp threat model there).
pub fn is_own_regular_file(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        match fs::symlink_metadata(path) {
            Ok(meta) => {
                let euid = unsafe { libc::geteuid() };
                meta.file_type().is_file() && meta.uid() == euid && (meta.mode() & 0o077) == 0
            }
            Err(_) => false,
        }
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

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

/// Return the resolved project directory path (git root, env override, or cwd).
pub fn project_dir() -> String {
    PROJECT_DIR.get_or_init(resolve_project_dir).clone()
}

/// Return the basename of the resolved project directory (git-root basename or cwd basename).
/// Used as the default --project value for `hiboss progress post`.
pub fn project_name() -> String {
    let dir = PROJECT_DIR.get_or_init(resolve_project_dir);
    std::path::Path::new(dir.as_str())
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(dir.as_str())
        .to_owned()
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

/// Marker: stop hook already warned once this session — don't block again.
pub fn stop_warned_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-stop-warned-{}", project_hash()))
}

pub fn mark_stop_warned() {
    let _ = fs::write(stop_warned_marker_path(), "1");
}

pub fn has_stop_warned() -> bool {
    stop_warned_marker_path().exists()
}

/// Marker: the Stop hook parked this session as "waiting" (idle, awaiting the
/// boss). Set on Stop, consumed by the next background heartbeat so a session
/// that resumed work is flipped back to "working" instead of lingering as
/// waiting. Existence flag only — never printed into agent context.
pub fn resume_pending_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-resume-pending-{}", project_hash()))
}

/// Record that the Stop hook parked this session as waiting.
pub fn mark_resume_pending() {
    let _ = fs::write(resume_pending_marker_path(), "1");
}

/// Consume the resume-pending marker: returns true (and deletes it) when the
/// session was parked as waiting and should now be reset to working. The next
/// bg-check only runs because active work resumed, so consuming it there is the
/// resume signal.
pub fn take_resume_pending() -> bool {
    let path = resume_pending_marker_path();
    if path.exists() {
        let _ = fs::remove_file(&path);
        true
    } else {
        false
    }
}

/// Clear the resume-pending marker without acting on it — a manually set status
/// (`hiboss ss`) wins, so bg-check must not later override it with "working".
pub fn clear_resume_pending() {
    let _ = fs::remove_file(resume_pending_marker_path());
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

/// Marker file: written when agent broadcasts to peers, checked by Stop hook.
pub fn broadcast_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-broadcast-{}", project_hash()))
}

/// Record that agent broadcast to peers this session.
pub fn mark_broadcast() {
    let _ = fs::write(broadcast_marker_path(), "1");
}

/// Check whether agent has broadcast to peers this session.
pub fn has_broadcast() -> bool {
    broadcast_marker_path().exists()
}

/// Marker file: tracks whether peers were active during this session.
pub fn peers_active_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-peers-active-{}", project_hash()))
}

/// Record that peer sessions were detected during this session.
pub fn mark_peers_active() {
    let _ = fs::write(peers_active_marker_path(), "1");
}

/// Check whether peer sessions were active during this session.
pub fn had_peers_active() -> bool {
    peers_active_marker_path().exists()
}

/// TTL file for broadcast reminders (avoid spamming every PostToolUse).
pub fn broadcast_remind_ttl_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-broadcast-remind-{}", project_hash()))
}

/// Queue file for message IDs to be marked as read by bg-check.
pub fn read_queue_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-read-queue-{}", project_hash()))
}

/// Append message IDs to the read queue (one per line).
pub fn queue_mark_read(ids: &[&str]) {
    if ids.is_empty() {
        return;
    }
    let content = ids.join("\n") + "\n";
    // Append to file
    let path = read_queue_path();
    let existing = fs::read_to_string(&path).unwrap_or_default();
    let _ = write_private(&path, &format!("{}{}", existing, content));
}

/// Drain message IDs from the read queue. Returns IDs to mark.
pub fn drain_read_queue() -> Vec<String> {
    let path = read_queue_path();
    let tmp = path.with_extension("draining");
    if fs::rename(&path, &tmp).is_err() {
        return vec![];
    }
    let content = fs::read_to_string(&tmp).unwrap_or_default();
    let _ = fs::remove_file(&tmp);
    content
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_owned())
        .collect()
}

/// Marker file: tracks whether the ack hint has been shown this session.
pub fn ack_hint_shown_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-ack-hint-{}", project_hash()))
}

/// Show ack hint only once per session; returns true if hint should be printed.
pub fn should_show_ack_hint() -> bool {
    let path = ack_hint_shown_path();
    if path.exists() {
        return false;
    }
    let _ = fs::write(&path, "1");
    true
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
    // Atomic read-and-truncate: rename then read. The rename moves the inode, so
    // the post-rename ownership check applies to the exact bytes we will read
    // (closing the TOCTOU window). These lines are injected into the agent context
    // as trusted [boss]/[peer] messages, so a spool a co-resident user planted or
    // tampered with must never be drained.
    let tmp = path.with_extension("draining");
    if fs::rename(&path, &tmp).is_err() {
        return vec![];
    }
    if !is_own_regular_file(&tmp) {
        let _ = fs::remove_file(&tmp);
        return vec![];
    }
    let content = fs::read_to_string(&tmp).unwrap_or_default();
    let _ = fs::remove_file(&tmp);
    content
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_owned())
        .collect()
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
    write_private(&session_file_path(), id)
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

}
