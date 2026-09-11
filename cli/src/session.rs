// Purpose: Read/write per-project session IDs for message isolation.
// Exports: session_file_path, read_session_id, write_session_id, project_hash.
// Dependencies: std::fs, std::env, std::sync::OnceLock.

mod project;
mod markers;
pub use project::{ProjectIdentity, resolve_project};
pub use markers::*;
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

/// Path to the session-local producer epoch held for one panel.
pub fn panel_epoch_file_path(panel_id: &str) -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-session-{}-panel-{panel_id}-epoch", project_hash()))
}

/// Read the epoch last claimed by this session for one panel.
pub fn read_panel_epoch(panel_id: &str) -> Option<String> {
    let path = panel_epoch_file_path(panel_id);
    if !is_own_regular_file(&path) {
        return None;
    }
    fs::read_to_string(path).ok().map(|body| body.trim().to_owned()).filter(|body| !body.is_empty())
}

/// Record or clear a panel epoch in the same private temporary area as session state.
pub fn write_panel_epoch(panel_id: &str, epoch: Option<&str>) -> Result<(), Box<dyn std::error::Error>> {
    let path = panel_epoch_file_path(panel_id);
    match epoch {
        Some(epoch) => write_private(&path, epoch)?,
        None => {
            if let Err(error) = fs::remove_file(path) {
                if error.kind() != std::io::ErrorKind::NotFound {
                    return Err(error.into());
                }
            }
        }
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

    #[cfg(unix)]
    #[test]
    fn panel_epoch_rejects_non_private_files() {
        use std::os::unix::fs::PermissionsExt;
        let panel_id = format!("session-permission-{}", std::process::id());
        let path = panel_epoch_file_path(&panel_id);
        write_private(&path, "foreign").expect("write epoch");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).expect("chmod epoch");
        assert_eq!(read_panel_epoch(&panel_id), None);
        let _ = fs::remove_file(path);
    }

}
