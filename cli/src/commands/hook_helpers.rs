// Purpose: Utility functions for hiboss CLI hook events.
// Exports: start/stop/restart of the session daemon, build_client, get_git_branch,
//          show_peer_sessions, generate_session_id, get_inbox_count, get_a2a_inbox_count.

use crate::{client::HiBossClient, config, session};
use std::error::Error;
use std::fs;
use std::io::Read;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) const BOSS_TTL_SECONDS: u64 = 300;
pub(crate) const A2A_TTL_SECONDS: u64 = 30;

/// Start this session's SSE daemon unless one is running; returns its pid.
pub(crate) fn start_daemon_if_needed() -> Result<u32, Box<dyn Error>> {
    if let Some(pid) = session::is_daemon_running() {
        return Ok(pid);
    }
    let exe = std::env::current_exe()?;
    let log = session::open_log(session::DAEMON_LOG)?;
    let child = Command::new(&exe)
        .args(["daemon", "run"])
        .stdout(log.try_clone()?)
        .stderr(log)
        .stdin(std::process::Stdio::null())
        .spawn()?;
    session::write_state(session::DAEMON_PID, &child.id().to_string())?;
    Ok(child.id())
}

/// Kill this session's SSE daemon if it is running; returns the pid it stopped.
pub(crate) fn stop_daemon() -> Option<u32> {
    let pid = session::is_daemon_running();
    if let Some(pid) = pid {
        let _ = Command::new("kill").arg(pid.to_string()).output();
    }
    session::remove_state(session::DAEMON_PID);
    pid
}

/// Restart a running daemon so its SSE subscription carries the current session id.
pub(crate) fn restart_daemon_if_running() {
    if stop_daemon().is_some() {
        if let Err(err) = start_daemon_if_needed() {
            eprintln!("hiboss: daemon restart failed: {err}");
        }
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

/// Show active peer sessions for cross-session collaboration. Returns true if peers exist.
pub(crate) async fn show_peer_sessions(my_session_id: &str) -> bool {
    let client = match build_client() {
        Ok(c) => c,
        Err(_) => return false,
    };
    let sessions = match client.list_sessions().await {
        Ok(s) => s,
        Err(_) => return false,
    };
    let peers: Vec<_> = sessions
        .sessions
        .iter()
        .filter(|s| s.id != my_session_id && s.status.as_deref() != Some("completed"))
        .collect();
    if !peers.is_empty() {
        session::mark_peers_active();
        println!("Active peer sessions (use hiboss send --broadcast to notify all):");
        for s in &peers {
            let id_short: String = s.id.chars().take(8).collect();
            let label = s.label.as_deref().unwrap_or("-");
            let status = s.status.as_deref().unwrap_or("working");
            let icon = match status {
                "working" => "🔨",
                "blocked" => "🚫",
                "waiting" => "⏳",
                "idle" => "💤",
                "completed" => "✅",
                _ => "•",
            };
            let status_text = s.status_text.as_deref().unwrap_or("");
            let detail = if status_text.is_empty() {
                format!("{} {}", icon, status)
            } else if status_text.len() > 60 {
                let truncate_at = status_text
                    .char_indices()
                    .map(|(i, _)| i)
                    .take_while(|&i| i <= 57)
                    .last()
                    .unwrap_or(0);
                format!("{} {}: {}...", icon, status, &status_text[..truncate_at])
            } else {
                format!("{} {}: {}", icon, status, status_text)
            };
            println!("  {}  {}  {}", id_short, label, detail);
        }
        println!(
            "COORDINATE: If peer communication is authorized, broadcast your plan: hiboss send --broadcast \"Working on X\""
        );
        return true;
    }
    false
}

/// TTL for broadcast reminders in PostToolUse (10 minutes).
pub(crate) const BROADCAST_REMIND_TTL_SECONDS: u64 = 600;

/// Generate a UUID v4-style session ID from /dev/urandom.
pub(crate) fn generate_session_id() -> String {
    let mut buf = [0u8; 16];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    } else {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
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
    let output = Command::new("hiboss")
        .args(["inbox", "--count"])
        .output()
        .ok();
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
