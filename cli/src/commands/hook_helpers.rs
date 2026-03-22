// Purpose: Utility functions for hiboss CLI hook events.
// Exports: is_ttl_expired, start_daemon_if_needed, build_client, get_git_branch, 
//          show_peer_sessions, generate_session_id, get_inbox_count, get_a2a_inbox_count.

use crate::{client::HiBossClient, config, session};
use std::error::Error;
use std::fs;
use std::io::Read;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) const BOSS_TTL_SECONDS: u64 = 300;
pub(crate) const A2A_TTL_SECONDS: u64 = 30;

pub(crate) fn is_ttl_expired(path: &std::path::Path, now: u64, ttl: u64) -> bool {
    match fs::read_to_string(path) {
        Ok(content) => match content.trim().parse::<u64>() {
            Ok(last) => now.saturating_sub(last) >= ttl,
            Err(_) => true,
        },
        Err(_) => true,
    }
}

/// Start the SSE daemon if not already running.
pub(crate) fn start_daemon_if_needed() {
    if session::is_daemon_running().is_some() {
        return;
    }
    // Best-effort: start daemon in background
    let exe = match std::env::current_exe() {
        Ok(e) => e,
        Err(_) => return,
    };
    let log_path = format!("/tmp/hiboss-daemon-{}.log", session::project_hash());
    let child = Command::new(&exe)
        .args(["daemon", "run"])
        .stdout(fs::File::create(&log_path).unwrap_or_else(|_| fs::File::create("/dev/null").unwrap()))
        .stderr(fs::File::create(&log_path).unwrap_or_else(|_| fs::File::create("/dev/null").unwrap()))
        .stdin(std::process::Stdio::null())
        .spawn();
    if let Ok(child) = child {
        let _ = fs::write(session::daemon_pid_path(), child.id().to_string());
    }
}

/// Build an HiBossClient from config (best-effort, returns Err if not configured).
pub(crate) fn build_client() -> Result<HiBossClient, Box<dyn Error>> {
    let cfg = config::load_config()?;
    let server = cfg.require_server()?;
    let key = cfg.require_key()?;
    Ok(HiBossClient::new(&server, &key))
}

/// Get current git branch name.
pub(crate) fn get_git_branch() -> Option<String> {
    Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(String::from_utf8_lossy(&o.stdout).trim().to_owned())
            } else {
                None
            }
        })
}

/// Get repo name from git remote origin URL, falling back to directory name.
pub(crate) fn get_repo_name() -> Option<String> {
    // Try git remote origin URL first (e.g. git@github.com:user/repo.git -> repo)
    if let Some(name) = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .output()
        .ok()
        .and_then(|o| if o.status.success() { Some(String::from_utf8_lossy(&o.stdout).trim().to_owned()) } else { None })
        .and_then(|url| {
            let s = url.trim_end_matches(".git");
            s.rsplit('/').next().map(|n| n.to_owned())
        })
    {
        if !name.is_empty() { return Some(name); }
    }
    // Fall back to cwd directory name
    std::env::current_dir().ok().and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
}

/// Show active peer sessions for cross-session collaboration.
pub(crate) async fn show_peer_sessions(my_session_id: &str) {
    let client = match build_client() {
        Ok(c) => c,
        Err(_) => return,
    };
    let sessions = match client.list_sessions().await {
        Ok(s) => s,
        Err(_) => return,
    };
    let peers: Vec<_> = sessions.sessions.iter()
        .filter(|s| s.id != my_session_id)
        .collect();
    if !peers.is_empty() {
        println!("Active peer sessions (use hiboss send --to <label-or-id> to message):");
        for s in &peers {
            let id_short: String = s.id.chars().take(8).collect();
            let label = s.label.as_deref().unwrap_or("-");
            let agent = s.agent_name.as_deref().unwrap_or(&s.agent_id);
            println!("  {}  {}  ({})", id_short, label, agent);
        }
    }
}

/// Generate a UUID v4-style session ID from /dev/urandom.
pub(crate) fn generate_session_id() -> String {
    let mut buf = [0u8; 16];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    } else {
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
        let pid = std::process::id() as u128;
        let val = ts ^ (pid << 64);
        buf = val.to_le_bytes();
    }
    buf[6] = (buf[6] & 0x0f) | 0x40;
    buf[8] = (buf[8] & 0x3f) | 0x80;
    format!(
        "{:08x}-{:04x}-{:04x}-{:04x}-{:012x}",
        u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]),
        u16::from_be_bytes([buf[4], buf[5]]),
        u16::from_be_bytes([buf[6], buf[7]]),
        u16::from_be_bytes([buf[8], buf[9]]),
        u64::from_be_bytes([0, 0, buf[10], buf[11], buf[12], buf[13], buf[14], buf[15]]),
    )
}

pub(crate) fn get_inbox_count() -> u32 {
    let output = Command::new("hiboss").args(["inbox", "--count"]).output().ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}

pub(crate) fn get_a2a_inbox_count() -> u32 {
    let output = Command::new("hiboss")
        .args(["inbox", "--direction", "agent_to_agent", "--count"])
        .output()
        .ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}
