// Purpose: Provide the Claude Code hook orchestration for hiboss CLI events.
// Exports: HookArgs, HookEvent, run().
// Dependencies: clap, crate::client, crate::config, crate::session, std::fs, std::process, std::time.

use crate::session;
use clap::{Args, Subcommand};
use std::error::Error;
use std::io::Write;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use super::hook_helpers::*;
use super::hook_unacked::unacknowledged_outbound_warning;

#[derive(Debug, Args)]
pub struct HookArgs {
    #[arg(
        long,
        help = "Read Codex hook JSON from stdin and use its session/project context"
    )]
    pub codex_input: bool,
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
    #[command(about = "Mark the session waiting; keep its listener only if the session can be woken")]
    Stop,
}

pub async fn run(args: &HookArgs) -> Result<(), Box<dyn Error>> {
    if args.codex_input {
        return super::codex_hook::run(&args.event);
    }
    let _ = match &args.event {
        HookEvent::SessionStart => super::hook_start::run().await,
        HookEvent::PostToolUse => run_post_tool_use(),
        HookEvent::BgCheck => run_bg_check().await,
        // A dispatched agent reports to its dispatcher; Stop never waits on the boss.
        HookEvent::Stop if crate::runtime::RuntimeIdentity::detect().is_dispatched() => {
            stop_daemon();
            Ok(())
        }
        HookEvent::Stop => run_stop().await,
    };
    Ok(())
}

/// PostToolUse: purely local I/O, no HTTP; at most one detached bg-check. Returns in ~5ms.
fn run_post_tool_use() -> Result<(), Box<dyn Error>> {
    // Without a usable state directory there is no spool, TTL or session to work with.
    if session::state_dir().is_none() {
        return Ok(());
    }
    session::clear_idle();
    let mut context = Vec::new();
    print_pending_messages(&mut context)?;
    // Urgent notices enter the agent context, so they come only from the private state dir.
    if let Some(content) = session::take_urgent() {
        writeln!(context, "{}", content.trim())?;
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    super::hook_notes::announce_to(now, &mut context)?;
    remind_broadcast(now, &mut context)?;
    spawn_bg_check_if_due(now);
    if !context.is_empty() {
        let context = String::from_utf8(context)?;
        println!(
            "{}",
            serde_json::json!({"hookSpecificOutput": {
                "hookEventName": "PostToolUse", "additionalContext": context.trim_end()
            }})
        );
    }
    Ok(())
}

/// Print messages the daemon or an ask's waiter spooled and queue them for read marking by
/// bg-check. Both can spool the same reply, so each message id is shown once.
fn print_pending_messages(context: &mut impl Write) -> std::io::Result<()> {
    let mut seen = std::collections::HashSet::new();
    let pending: Vec<serde_json::Value> = session::drain_pending_messages()
        .iter()
        // A line spooled before the daemon verified its stream is checked here as well.
        .filter(|line| crate::message_security::parse_verified_message(line).is_ok())
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .filter(|msg| msg["id"].as_str().is_none_or(|id| id.is_empty() || seen.insert(id.to_owned())))
        .collect();
    if pending.is_empty() {
        return Ok(());
    }
    session::clear_woken();
    writeln!(context, "REAL-TIME: {} new messages arrived:", pending.len())?;
    let mut ids_to_mark: Vec<&str> = Vec::new();
    for msg in &pending {
        let body = msg["body"].as_str().unwrap_or("");
        let agent = msg["agent_name"].as_str().unwrap_or("-");
        let id = msg["id"].as_str().unwrap_or("");
        let id_short = &id[..8.min(id.len())];
        if msg["metadata"]["auto_default"] == true {
            // The server picked this on timeout; it must never read as the boss's answer.
            writeln!(context, "  [server default] ({id_short}): {body} (automatic timeout default; \
                not a boss decision or execution authorization)")?;
        } else {
            let from = if msg["direction"] == "agent_to_agent" { "peer" } else { "boss" };
            writeln!(context, "  [{from}] {agent} ({id_short}): {body}")?;
        }
        if !id.is_empty() {
            ids_to_mark.push(id);
        }
    }
    session::queue_mark_read(&ids_to_mark);
    writeln!(context, "Reply with: hiboss reply <id> \"response\"")
}

/// Remind about broadcasting if peers are active and no recent reminder was shown.
fn remind_broadcast(now: u64, context: &mut impl Write) -> std::io::Result<()> {
    if !session::had_peers_active()
        || !session::is_ttl_expired(session::BROADCAST_REMIND, now, BROADCAST_REMIND_TTL_SECONDS)
    {
        return Ok(());
    }
    session::stamp_ttl(session::BROADCAST_REMIND, now);
    writeln!(
        context,
        "BROADCAST REMINDER: You have active peer sessions. Share your progress:"
    )?;
    writeln!(
        context,
        "  hiboss send --broadcast \"<what you're working on and current status>\""
    )
}

/// Spawn a detached bg-check when either TTL expired, claiming the TTLs first.
fn spawn_bg_check_if_due(now: u64) {
    let a2a_expired = session::is_ttl_expired(session::A2A_CHECK, now, A2A_TTL_SECONDS);
    let boss_expired = session::is_ttl_expired(session::URGENT_CHECK, now, BOSS_TTL_SECONDS);
    let notes_expired = super::hook_notes::due(now);
    if !a2a_expired && !boss_expired && !notes_expired {
        return;
    }
    if notes_expired {
        super::hook_notes::claim(now);
    }
    if a2a_expired {
        session::stamp_ttl(session::A2A_CHECK, now);
    }
    if boss_expired {
        session::stamp_ttl(session::URGENT_CHECK, now);
    }
    if let Ok(exe) = std::env::current_exe() {
        let _ = Command::new(exe)
            .args(["hook", "bg-check"])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
}

/// Background HTTP checks: read marks, heartbeat, urgent inbox. Runs as detached process.
async fn run_bg_check() -> Result<(), Box<dyn Error>> {
    let client = match build_client() {
        Ok(c) => c,
        Err(_) => return Ok(()),
    };
    for id in &session::drain_read_queue() {
        let _ = client.update_status(id, "read").await;
    }
    let session_id = session::read_session_id();
    // Heartbeat. If a Stop parked this session as "waiting" and work has since resumed
    // (bg-check only runs off PostToolUse activity), flip it back to "working". Otherwise
    // leave status untouched so a manually set status (e.g. blocked) is preserved.
    if let Some(sid) = &session_id {
        super::hook_notes::refresh(&client, sid).await;
        let status = session::take_resume_pending().then_some("working");
        let _ = client.heartbeat_session(sid, status, None).await;
    }
    flag_unread_messages(&client, session_id.as_deref()).await;
    if let Some(sid) = &session_id {
        if let Some(warning) = unacknowledged_outbound_warning(&client, sid).await {
            session::append_urgent(&format!("{warning}\n"));
        }
    }
    Ok(())
}

/// Leave an urgent notice for the next PostToolUse: urgent boss messages, and peer messages
/// when no daemon is delivering them.
async fn flag_unread_messages(client: &crate::client::HiBossClient, session_id: Option<&str>) {
    let count = client
        .inbox_count(Some("critical,high"), session_id)
        .await
        .unwrap_or(0);
    if count > 0 {
        let msg = format!(
            "URGENT: You have {} unread critical/high priority boss messages. Run: hiboss inbox --priority critical,high\n",
            count
        );
        let _ = session::write_state(session::URGENT, &msg);
    }
    if session::is_daemon_running().is_some() {
        return;
    }
    let a2a_count = client.inbox_count_a2a(session_id).await.unwrap_or(0);
    if a2a_count > 0 {
        session::append_urgent(&format!(
            "PEER MESSAGE: You have {} unread agent-to-agent messages. Run: hiboss inbox --direction agent_to_agent\n",
            a2a_count
        ));
    }
}

async fn run_stop() -> Result<(), Box<dyn Error>> {
    // Best-effort: mark session waiting on server. Claude Code fires Stop on
    // every turn boundary, not process exit — so this is "idle, awaiting the
    // boss's next input", NOT "session ended". Marking it completed here made a
    // live session read as ended and misled operators about which session was
    // active. A truly gone session falls out of the active window via the
    // server's 15-minute last_seen_at staleness cutoff instead.
    if let (Ok(client), Some(sid)) = (build_client(), &session::read_session_id()) {
        let _ = client
            .heartbeat_session(sid, Some("waiting"), Some("Awaiting next input"))
            .await;
        // Arm the resume signal: the next bg-check (which only runs when work has
        // resumed) will flip this back to "working".
        session::mark_resume_pending();
    }
    park_listener().await;
    Ok(())
}

/// An idle Claude Code session keeps its daemon so a boss message can wake it through the
/// session socket; without a socket nothing could wake it, so the daemon stops as before.
async fn park_listener() {
    if super::daemon_wake::Inbox::from_env().is_none() {
        stop_daemon();
        return;
    }
    session::mark_idle();
    if let Err(err) = ensure_session_daemon() {
        eprintln!("hiboss: daemon start failed: {err}");
    }
    super::daemon_wake::wake_for_unread_spool(session::read_session_id().as_deref()).await;
}
