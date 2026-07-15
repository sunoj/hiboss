// Purpose: Provide the Claude Code hook orchestration for hiboss CLI events.
// Exports: HookArgs, HookEvent, run().
// Dependencies: clap, crate::client, crate::config, crate::session, std::fs, std::process, std::time.

use crate::session;
use clap::{Args, Subcommand};
use std::error::Error;
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use super::hook_helpers::*;

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
    // Clean up stale marker files from any previous session for this project.
    // These are per-project (keyed by project hash), so they persist across sessions
    // unless explicitly cleaned. Stop hook does NOT clean them (Claude Code fires Stop
    // on every exit attempt including user-cancelled ones).
    for path in [
        session::session_file_path(),
        session::asked_marker_path(),
        session::replied_marker_path(),
        session::ack_hint_shown_path(),
        session::stop_warned_marker_path(),
        session::broadcast_marker_path(),
        session::peers_active_marker_path(),
        session::broadcast_remind_ttl_path(),
        session::read_queue_path(),
        session::urgent_file_path(),
        session::daemon_pending_path(),
        session::ttl_file_path(),
        session::a2a_ttl_file_path(),
    ] {
        let _ = fs::remove_file(path);
    }

    // Idempotent: reuse existing session if file already exists (handles duplicate hooks)
    let session_id = if let Some(existing) = session::read_session_id() {
        existing
    } else {
        let id = generate_session_id();
        let _ = session::write_session_id(&id);

        // Resolve branch, cwd, and repo name for session registration
        let branch = get_git_branch();
        let cwd = std::env::current_dir()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()));
        let repo_name = get_repo_name();
        // Label: "repo/branch" for thread titles (e.g. "hiboss/main")
        let label = match (&repo_name, &branch) {
            (Some(r), Some(b)) => Some(format!("{}/{}", r, b)),
            (Some(r), None) => Some(r.clone()),
            _ => None,
        };

        // Register session with the server (best-effort)
        if let Ok(client) = build_client() {
            let _ = client.register_session(
                &id,
                branch.as_deref(),
                cwd.as_deref(),
                label.as_deref(),
                Some("working"),
                None,
            ).await;
            // Mark all existing messages as read so unread count starts at 0
            let _ = client.mark_all_read().await;
        }
        id
    };

    // Start background SSE daemon for real-time message delivery
    start_daemon_if_needed();

    println!("MANDATORY: hiboss is installed for boss communication. You MUST follow these rules:");
    println!("1. After completing any task or subtask, run: hiboss send \"<what you did and what's next>\"");
    println!("2. When blocked or need input, run: hiboss ask \"<your question>\"");
    println!("3. Reply to boss messages with: hiboss reply <id> \"<response>\"");
    println!("4. Check inbox with: hiboss inbox");
    println!("5. Send to peer sessions with: hiboss send --to <session-label-or-id> \"<message>\"");
    println!("6. Broadcast to ALL peer sessions: hiboss send --broadcast \"<what you're working on>\"");
    println!("CRITICAL: When task is complete, NEVER just stop. Run: hiboss ask --option \"Opt1\" --option \"Opt2\" \"summary and options\" (run_in_background), then WAIT for boss reply.");
    println!("CLI SYNTAX: Repeat singular --option or --action for each choice. Never use removed --options/--actions or comma-separated choice lists.");
    println!("IMPORTANT: When replying to PEER messages (from [agent]), use: hiboss reply <id> \"response\" — do NOT use hiboss send without --to, as that sends to the boss's Telegram/Discord.");
    println!("COORDINATE: When peer sessions are active, broadcast your work plan BEFORE starting: hiboss send --broadcast \"Working on X in files Y\"");
    println!("RULE: After receiving a boss reply from `hiboss ask`, ALWAYS acknowledge via `hiboss send \"<acknowledgment>\"` — NEVER just print text in conversation.");

    // Show peer sessions and auto-broadcast if peers exist
    let has_peers = show_peer_sessions(&session_id).await;
    if has_peers {
        auto_broadcast_session_start().await;
    }

    // Show unread boss messages
    let boss_count = get_inbox_count();
    let a2a_count = get_a2a_inbox_count();
    if boss_count > 0 || a2a_count > 0 {
        println!("You have {} unread messages:", boss_count + a2a_count);
        if let Ok(out) = Command::new("hiboss").args(["inbox"]).output() {
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
        let mut ids_to_mark: Vec<String> = Vec::new();
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
                if !id.is_empty() {
                    ids_to_mark.push(id.to_owned());
                }
            }
        }
        // Queue displayed messages for auto-read marking (bg-check will process)
        let id_refs: Vec<&str> = ids_to_mark.iter().map(|s| s.as_str()).collect();
        session::queue_mark_read(&id_refs);
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

    // 3. Remind about broadcasting if peers are active and no recent broadcast
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    if session::had_peers_active() {
        let remind_expired = is_ttl_expired(
            &session::broadcast_remind_ttl_path(), now, BROADCAST_REMIND_TTL_SECONDS,
        );
        if remind_expired {
            let _ = fs::write(session::broadcast_remind_ttl_path(), now.to_string());
            println!("BROADCAST REMINDER: You have active peer sessions. Share your progress:");
            println!("  hiboss send --broadcast \"<what you're working on and current status>\"");
        }
    }

    // 4. Spawn bg-check in background if any TTL expired (non-blocking)
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

    // Process read queue: mark displayed messages as read
    let read_ids = session::drain_read_queue();
    for id in &read_ids {
        let _ = client.update_status(id, "read").await;
    }

    // Heartbeat
    if let Some(sid) = session::read_session_id() {
        let _ = client.heartbeat_session(&sid, None, None).await;
    }

    // Urgent boss message check
    let count = match client.inbox_count(Some("critical,high"), session::read_session_id().as_deref()).await {
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
        let a2a_count = match client.inbox_count_a2a(session::read_session_id().as_deref()).await {
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
    // Only gate: must have called `hiboss ask` before exiting.
    // No cleanup here — Claude Code fires Stop on every exit attempt,
    // including ones the user cancels. Cleaning up markers here would
    // delete the asked-marker and cause false BLOCKED on the next attempt.
    // Session cleanup is handled by session-start (idempotent re-init).
    if !session::has_asked() {
        if session::has_stop_warned() {
            // Already prompted once this session — let it through
            return Ok(());
        }
        session::mark_stop_warned();
        // stdout: AI sees detailed instructions
        println!("BLOCKED: You cannot stop without asking the boss for next steps.");
        println!("Run: hiboss ask --option \"Opt1\" --option \"Opt2\" \"summary and options\"");
        let _ = std::io::Write::flush(&mut std::io::stdout());
        // stderr: human sees a short note
        eprintln!("ask boss first");
        std::process::exit(2);
    }

    // Best-effort: mark session completed on server
    if let (Ok(client), Some(sid)) = (build_client(), &session::read_session_id()) {
        let _ = client.heartbeat_session(sid, Some("completed"), Some("Session ended")).await;
    }
    // Kill SSE daemon if running
    if let Some(pid) = session::is_daemon_running() {
        let _ = Command::new("kill").arg(pid.to_string()).output();
        let _ = fs::remove_file(session::daemon_pid_path());
    }
    Ok(())
}
