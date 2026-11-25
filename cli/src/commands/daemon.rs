// Purpose: Background SSE daemon: spools messages for the hook and wakes an idle session for
// a reply, and a separate task wakes it for a boss note.
// Exports: DaemonCommand with start/stop/status subcommands.
// Dependencies: clap, tokio, crate::config, crate::session, crate::sse.

use crate::commands::SubcommandArgs;
use super::daemon_wake::{Inbox, Probe, deliver};
use super::hook_helpers::{start_daemon_if_needed, stop_daemon};
use super::note_wake;
use crate::{client::HiBossClient, config, session, sse};
use clap::Subcommand;
use std::error::Error;
use tokio::time::{Duration, sleep};

#[derive(Debug, Subcommand)]
pub enum DaemonCommand {
    #[command(about = "Start background SSE listener")]
    Start,
    #[command(about = "Stop background SSE listener")]
    Stop,
    #[command(about = "Check daemon status")]
    Status,
    #[command(about = "Run SSE loop (internal, called by start)")]
    Run,
}

pub async fn run(args: &SubcommandArgs<DaemonCommand>) -> Result<(), Box<dyn Error>> {
    match &args.command {
        DaemonCommand::Start => start_daemon(),
        DaemonCommand::Stop => stop_daemon_command(),
        DaemonCommand::Status => show_status(),
        DaemonCommand::Run => run_daemon().await,
    }
}

fn start_daemon() -> Result<(), Box<dyn Error>> {
    if let Some(pid) = session::is_daemon_running() {
        eprintln!("Daemon already running (pid {})", pid);
        return Ok(());
    }
    let pid = start_daemon_if_needed()?;
    let log = session::state_file(session::DAEMON_LOG).unwrap_or_default();
    eprintln!("Daemon started (pid {}, log: {})", pid, log.display());
    Ok(())
}

fn stop_daemon_command() -> Result<(), Box<dyn Error>> {
    match stop_daemon() {
        Some(pid) => eprintln!("Daemon stopped (pid {})", pid),
        None => eprintln!("Daemon not running"),
    }
    Ok(())
}

fn show_status() -> Result<(), Box<dyn Error>> {
    match session::is_daemon_running() {
        Some(pid) => {
            let count = session::read_state(session::DAEMON_PENDING)
                .map(|c| c.lines().filter(|l| !l.is_empty()).count())
                .unwrap_or(0);
            println!("running (pid {}, {} pending messages)", pid, count);
        }
        None => println!("stopped"),
    }
    Ok(())
}

/// Internal: run the SSE loop, spooling messages and waking an idle Claude Code session.
async fn run_daemon() -> Result<(), Box<dyn Error>> {
    let cfg = config::load_config()?;
    let server = cfg.require_server()?;
    let key = cfg.require_key()?;
    let session_id = session::read_session_id();
    let inbox = Inbox::from_env();
    let mut sse_url = format!("{}/api/messages/stream", server);
    if let Some(ref sid) = session_id {
        sse_url = format!("{}?session={}", sse_url, sid);
    }
    // The server sends a keepalive every 15 s; a silent socket (a sleep, a dropped route) is dead.
    let sse_client = reqwest::Client::builder().read_timeout(STREAM_READ_TIMEOUT).build()?;
    eprintln!("Daemon SSE connecting to {} (session wake {})", sse_url,
        if inbox.is_some() { "on" } else { "off" });

    // Notes poll in their own task, so a slow request never holds up the reply stream.
    if let Some(inbox) = inbox.clone() {
        tokio::spawn(note_wake::run(HiBossClient::new(&server, &key), inbox));
    }
    let mut backoff = RETRY_MIN;
    loop {
        if inbox.as_ref().is_some_and(|inbox| inbox.probe() == Probe::Gone) {
            break;
        }
        let (tx, mut rx) = tokio::sync::mpsc::channel::<sse::SseEvent>(32);
        let (url, k, client) = (sse_url.clone(), key.clone(), sse_client.clone());
        let stream = tokio::spawn(async move {
            sse::connect_sse(&client, &url, &k, tx).await.map_err(|err| err.to_string())
        });
        while let Some(event) = rx.recv().await {
            if event.event_type == "message" && deliver(&event.data, inbox.as_ref(), session_id.as_deref()).await {
                exit_with_session();
                return Ok(());
            }
        }
        sleep(next_delay(stream.await, &mut backoff)).await;
    }
    exit_with_session();
    Ok(())
}

const RETRY_MIN: Duration = Duration::from_secs(5);
const RETRY_MAX: Duration = Duration::from_secs(60);
const RECONNECT_AFTER_CLOSE: Duration = Duration::from_millis(250);
const STREAM_READ_TIMEOUT: Duration = Duration::from_secs(45);

/// The server ends every stream after a few minutes, and the next one only carries messages
/// created after it opens, so a stream that sent data reconnects at once. A stream that ended
/// without a byte (the server's error path) or failed backs off like a refused connect.
fn next_delay(outcome: Result<Result<bool, String>, tokio::task::JoinError>, backoff: &mut Duration) -> Duration {
    let reason = match outcome {
        Ok(Ok(true)) => {
            *backoff = RETRY_MIN;
            return RECONNECT_AFTER_CLOSE;
        }
        Ok(Ok(false)) => "ended without data".to_owned(),
        Ok(Err(err)) => err,
        Err(err) => err.to_string(),
    };
    let delay = *backoff;
    eprintln!("SSE stream failed ({reason}), reconnecting in {}s...", delay.as_secs());
    *backoff = (delay * 2).min(RETRY_MAX);
    delay
}

/// The Claude Code process this daemon served has exited; release its pid file if still ours.
fn exit_with_session() {
    eprintln!("Session socket is gone; daemon exiting");
    let own = std::process::id().to_string();
    if session::read_state(session::DAEMON_PID).is_some_and(|pid| pid.trim() == own) {
        session::remove_state(session::DAEMON_PID);
        session::remove_state(session::DAEMON_SOCKET);
    }
}
