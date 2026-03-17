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

const TTL_SECONDS: u64 = 300;

#[derive(Debug, Args)]
pub struct HookArgs {
    #[command(subcommand)]
    pub event: HookEvent,
}

#[derive(Debug, Subcommand)]
pub enum HookEvent {
    #[command(about = "Check unread messages at session start")]
    SessionStart,
    #[command(about = "Check urgent messages (TTL-cached, 5 min)")]
    PostToolUse,
    #[command(about = "No-op (kept for backward compatibility)")]
    Stop,
}

pub async fn run(args: &HookArgs) -> Result<(), Box<dyn Error>> {
    let _ = match &args.event {
        HookEvent::SessionStart => run_session_start().await,
        HookEvent::PostToolUse => run_post_tool_use().await,
        HookEvent::Stop => Ok(()),
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
        ).await;
    }

    println!("MANDATORY: hiboss is installed for boss communication. You MUST follow these rules:");
    println!("1. After completing any task or subtask, run: hiboss send \"<what you did and what's next>\"");
    println!("2. When blocked or need input, run: hiboss ask \"<your question>\"");
    println!("3. Reply to boss messages with: hiboss reply <id> \"<response>\"");
    println!("4. Check inbox with: hiboss inbox");
    println!("5. Send to peer sessions with: hiboss send --to <session-label-or-id> \"<message>\"");
    println!("CRITICAL: When task is complete, NEVER just stop. Run: hiboss ask --options \"Opt1,Opt2\" \"summary and options\" --timeout 300 (run_in_background), then WAIT for boss reply.");

    // Show peer sessions
    show_peer_sessions(&session_id).await;

    let count = get_inbox_count();
    if count > 0 {
        println!("You have {} unread messages:", count);
        if let Ok(out) = Command::new("hiboss").args(["inbox", "--ack"]).output() {
            print!("{}", String::from_utf8_lossy(&out.stdout));
        }
        println!("Handle these messages first. Reply with: hiboss reply <id> \"response\"");
    }
    Ok(())
}

async fn run_post_tool_use() -> Result<(), Box<dyn Error>> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let ttl_file = session::ttl_file_path();
    if let Ok(content) = fs::read_to_string(&ttl_file) {
        if let Ok(last_check) = content.trim().parse::<u64>() {
            if now.saturating_sub(last_check) < TTL_SECONDS {
                return Ok(());
            }
        }
    }

    let _ = fs::write(&ttl_file, now.to_string());

    // Heartbeat: update session last_seen_at
    if let (Ok(client), Some(sid)) = (build_client(), session::read_session_id()) {
        let _ = client.heartbeat_session(&sid).await;
    }

    let count = get_priority_inbox_count("critical,high");
    if count > 0 {
        println!("URGENT: You have {} unread critical/high priority messages. Run: hiboss inbox --priority critical,high", count);
    }
    Ok(())
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

fn get_priority_inbox_count(priority: &str) -> u32 {
    let output = Command::new("hiboss")
        .args(["inbox", "--priority", priority, "--count"])
        .output()
        .ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}
