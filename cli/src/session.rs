// Purpose: Read/write per-project session IDs for message isolation.
// Exports: session_file_path, read_session_id, write_session_id, project_hash.
// Dependencies: std::fs, std::env, sha2 (via simple hash).

use std::fs;
use std::path::PathBuf;

/// Derive a short project hash from cwd for per-project session files.
pub fn project_hash() -> String {
    let cwd = std::env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();
    // Simple FNV-1a hash → 16 hex chars
    let mut h: u64 = 0xcbf29ce484222325;
    for b in cwd.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", h)
}

/// Path to the session file: /tmp/hiboss-session-<project_hash>
pub fn session_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-session-{}", project_hash()))
}

/// Path to per-session TTL file for urgent checks.
pub fn ttl_file_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-urgent-check-{}", project_hash()))
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
