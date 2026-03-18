// Purpose: Provide the Claude Code hook orchestration for hiboss CLI events.
// Exports: HookArgs, HookEvent, run().
// Dependencies: clap, crate::client, crate::config, crate::session, std::fs, std::process, std::time.

use crate::{client::HiBossClient, config, session};
use clap::{Args, Subcommand};
use std::error::Error;
use std::fs;
use std::io::Read;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const BOSS_TTL_SECONDS: u64 = 300;
const A2A_TTL_SECONDS: u64 = 30;

#[derive(Debug, Args)]
pub struct HookArgs {
    #[command(subcommand)]
    pub event: HookEvent,
}

#[derive(Debug, Subcommand)]
pub enum HookEvent {
    #[command(about = "Check unread messages at session start")]
    SessionStart,
    #[command(about = "Drain local messages (no HTTP, instant return)")]
    PostToolUse,
    #[command(about = "Background HTTP checks (heartbeat, urgent inbox)")]
    BgCheck,
    #[command(about = "No-op (kept for backward compatibility)")]
    Stop,
}

pub async fn run(args: &HookArgs) -> Result<(), Box<dyn Error>> {
    let _ = match &args.event {
        HookEvent::SessionStart => run_session_start().await,
        HookEvent::PostToolUse => run_post_tool_use(),
        HookEvent::BgCheck => run_bg_check().await,
        HookEvent::Stop => run_stop().await,
    };
    Ok(())
}

async fn run_session_start() -> Result<(), Box<dyn Error>> {
    // Generate a unique session ID for message isolation
    let session_id = generate_session_id();
    let _ = session::write_session_id(&session_id);

    // Resolve branch and cwd for session registration
    let branch = get_git_branch();
    let cwd = std::env::current_dir()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()));

    // Register session with the server (best-effort)
    if let Ok(client) = build_client() {
        let _ = client.register_session(
            &session_id,
            branch.as_deref(),
            cwd.as_deref(),
            None,
            Some("working"),
            None,
        ).await;
    }

    // Start background SSE daemon for real-time message delivery
    start_daemon_if_needed();

    println!("MANDATORY: hiboss is installed for boss communication. You MUST follow these rules:");
    println!("1. After completing any task or subtask, run: hiboss send \"<what you did and what's next>\"");
    println!("2. When blocked or need input, run: hiboss ask \"<your question>\"");
    println!("3. Reply to boss messages with: hiboss reply <id> \"<response>\"");
    println!("4. Check inbox with: hiboss inbox");
    println!("5. Send to peer sessions with: hiboss send --to <session-label-or-id> \"<message>\"");
    println!("CRITICAL: When task is complete, NEVER just stop. Run: hiboss ask --options \"Opt1,Opt2\" \"summary and options\" --timeout 300 (run_in_background), then WAIT for boss reply.");
    println!("IMPORTANT: When replying to PEER messages (from [agent]), use: hiboss reply <id> \"response\" — do NOT use hiboss send without --to, as that sends to the boss's Telegram/Discord.");

    // Show peer sessions
    show_peer_sessions(&session_id).await;

    // Show unread boss messages
    let boss_count = get_inbox_count();
    let a2a_count = get_a2a_inbox_count();
    if boss_count > 0 || a2a_count > 0 {
        println!("You have {} unread messages:", boss_count + a2a_count);
        if let Ok(out) = Command::new("hiboss").args(["inbox", "--ack"]).output() {
            print!("{}", String::from_utf8_lossy(&out.stdout));
        }
        println!("Handle these messages first. Reply with: hiboss reply <id> \"response\"");
    }
    Ok(())
}

/// PostToolUse: purely local I/O, no HTTP, no subprocess. Returns in ~5ms.
fn run_post_tool_use() -> Result<(), Box<dyn Error>> {
    // 1. Drain pending messages from daemon's local file (fast, no I/O beyond file read)
    let pending = session::drain_pending_messages();
    if !pending.is_empty() {
        println!("REAL-TIME: {} new messages arrived via SSE daemon:", pending.len());
        for line in &pending {
            if let Ok(msg) = serde_json::from_str::<serde_json::Value>(line) {
                let direction = msg["direction"].as_str().unwrap_or("");
                let body = msg["body"].as_str().unwrap_or("");
                let agent = msg["agent_name"].as_str().unwrap_or("-");
                let id = msg["id"].as_str().unwrap_or("");
                let id_short = &id[..8.min(id.len())];
                if direction == "agent_to_agent" {
                    println!("  [peer] {} ({}): {}", agent, id_short, body);
                } else {
                    println!("  [boss] {} ({}): {}", agent, id_short, body);
                }
            }
        }
        println!("Reply with: hiboss reply <id> \"response\"");
    }

    // 2. Check if any urgent messages were flagged by bg-check (local file)
    let urgent_file = session::urgent_file_path();
    if let Ok(content) = fs::read_to_string(&urgent_file) {
        let content = content.trim();
        if !content.is_empty() {
            print!("{}", content);
            let _ = fs::write(&urgent_file, "");
        }
    }

    // 3. Spawn bg-check in background if any TTL expired (non-blocking)
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let a2a_expired = is_ttl_expired(&session::a2a_ttl_file_path(), now, A2A_TTL_SECONDS);
    let boss_expired = is_ttl_expired(&session::ttl_file_path(), now, BOSS_TTL_SECONDS);
    if a2a_expired || boss_expired {
        // Claim TTL immediately to prevent concurrent spawns
        if a2a_expired {
            let _ = fs::write(session::a2a_ttl_file_path(), now.to_string());
        }
        if boss_expired {
            let _ = fs::write(session::ttl_file_path(), now.to_string());
        }
        // Spawn bg-check detached — fire and forget
        if let Ok(exe) = std::env::current_exe() {
            let _ = Command::new(exe)
                .args(["hook", "bg-check"])
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
        }
    }
    Ok(())
}

/// Background HTTP checks: heartbeat + urgent inbox. Runs as detached process.
async fn run_bg_check() -> Result<(), Box<dyn Error>> {
    let client = match build_client() {
        Ok(c) => c,
        Err(_) => return Ok(()),
    };

    // Heartbeat
    if let Some(sid) = session::read_session_id() {
        let _ = client.heartbeat_session(&sid, None, None).await;
    }

    // Urgent boss message check
    let count = match client.inbox_count(Some("critical,high")).await {
        Ok(c) => c,
        Err(_) => 0,
    };
    if count > 0 {
        // Write to urgent file for next post-tool-use to pick up
        let msg = format!(
            "URGENT: You have {} unread critical/high priority boss messages. Run: hiboss inbox --priority critical,high\n",
            count
        );
        let _ = fs::write(session::urgent_file_path(), msg);
    }

    // A2A message check (only when daemon not running)
    if session::is_daemon_running().is_none() {
        let a2a_count = match client.inbox_count_a2a().await {
            Ok(c) => c,
            Err(_) => 0,
        };
        if a2a_count > 0 {
            let msg = format!(
                "PEER MESSAGE: You have {} unread agent-to-agent messages. Run: hiboss inbox --direction agent_to_agent\n",
                a2a_count
            );
            let urgent_file = session::urgent_file_path();
            let existing = fs::read_to_string(&urgent_file).unwrap_or_default();
            let _ = fs::write(&urgent_file, format!("{}{}", existing, msg));
        }
    }
    Ok(())
}

async fn run_stop() -> Result<(), Box<dyn Error>> {
    // Mark session as completed on the server
    if let (Ok(client), Some(sid)) = (build_client(), session::read_session_id()) {
        let _ = client.heartbeat_session(&sid, Some("completed"), Some("Session ended")).await;
    }
    // Stop the SSE daemon
    if let Some(pid) = session::is_daemon_running() {
        let _ = Command::new("kill").arg(pid.to_string()).output();
        let _ = fs::remove_file(session::daemon_pid_path());
    }
    // Clean up temp files
    let _ = fs::remove_file(session::session_file_path());
    let _ = fs::remove_file(session::ttl_file_path());
    let _ = fs::remove_file(session::a2a_ttl_file_path());
    let _ = fs::remove_file(session::daemon_pending_path());
    let _ = fs::remove_file(session::urgent_file_path());
    Ok(())
}

fn is_ttl_expired(path: &std::path::Path, now: u64, ttl: u64) -> bool {
    match fs::read_to_string(path) {
        Ok(content) => match content.trim().parse::<u64>() {
            Ok(last) => now.saturating_sub(last) >= ttl,
            Err(_) => true,
        },
        Err(_) => true,
    }
}

/// Start the SSE daemon if not already running.
fn start_daemon_if_needed() {
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
fn build_client() -> Result<HiBossClient, Box<dyn Error>> {
    let cfg = config::load_config()?;
    let server = cfg.require_server()?;
    let key = cfg.require_key()?;
    Ok(HiBossClient::new(&server, &key))
}

/// Get current git branch name.
fn get_git_branch() -> Option<String> {
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

/// Show active peer sessions for cross-session collaboration.
async fn show_peer_sessions(my_session_id: &str) {
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
fn generate_session_id() -> String {
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

fn get_inbox_count() -> u32 {
    let output = Command::new("hiboss").args(["inbox", "--count"]).output().ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}

fn get_a2a_inbox_count() -> u32 {
    let output = Command::new("hiboss")
        .args(["inbox", "--direction", "agent_to_agent", "--count"])
        .output()
        .ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}
