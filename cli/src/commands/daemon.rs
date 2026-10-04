// Purpose: Background SSE daemon for real-time message delivery via local file.
// Exports: DaemonArgs with start/stop/status subcommands.
// Dependencies: clap, tokio, crate::config, crate::session, crate::sse.

use super::hook_helpers::{start_daemon_if_needed, stop_daemon};
use crate::{config, session, sse};
use clap::{Args, Subcommand};
use std::error::Error;
use tokio::time::{Duration, sleep};

#[derive(Debug, Args)]
pub struct DaemonArgs {
    #[command(subcommand)]
    pub command: DaemonCommand,
}

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

pub async fn run(args: &DaemonArgs) -> Result<(), Box<dyn Error>> {
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

/// Internal: run the SSE loop, writing messages to the pending file.
async fn run_daemon() -> Result<(), Box<dyn Error>> {
    let cfg = config::load_config()?;
    let server = cfg.require_server()?;
    let key = cfg.require_key()?;
    let session_id = session::read_session_id();
    let mut sse_url = format!("{}/api/messages/stream", server);
    if let Some(ref sid) = session_id {
        sse_url = format!("{}?session={}", sse_url, sid);
    }
    let sse_client = reqwest::Client::new();
    eprintln!("Daemon SSE connecting to {}", sse_url);

    let mut backoff = 5u64;
    loop {
        let (tx, mut rx) = tokio::sync::mpsc::channel::<sse::SseEvent>(32);
        let url = sse_url.clone();
        let k = key.clone();
        let client = sse_client.clone();
        tokio::spawn(async move {
            let _ = sse::connect_sse(&client, &url, &k, tx).await;
        });

        // Process received messages until channel closes (SSE disconnected). The spool
        // holds message bodies the hook injects into the agent context, so it is only ever
        // appended as a private file in the validated state directory.
        while let Some(event) = rx.recv().await {
            if event.event_type == "message" {
                let _ = session::append_state(session::DAEMON_PENDING, &format!("{}\n", event.data));
            }
            backoff = 5;
        }

        eprintln!("SSE stream closed, reconnecting in {}s...", backoff);
        sleep(Duration::from_secs(backoff)).await;
        backoff = (backoff * 2).min(60);
    }
}
