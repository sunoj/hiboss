// Purpose: Background SSE daemon for real-time message delivery via local file.
// Exports: DaemonArgs with start/stop/status subcommands.
// Dependencies: clap, tokio, crate::config, crate::session, crate::sse.

use crate::{config, session, sse};
use clap::{Args, Subcommand};
use std::error::Error;
use std::fs;
use std::io::Write;
use std::process::Command;
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
        DaemonCommand::Stop => stop_daemon(),
        DaemonCommand::Status => show_status(),
        DaemonCommand::Run => run_daemon().await,
    }
}

fn start_daemon() -> Result<(), Box<dyn Error>> {
    if let Some(pid) = session::is_daemon_running() {
        eprintln!("Daemon already running (pid {})", pid);
        return Ok(());
    }
    let exe = std::env::current_exe()?;
    let cwd = std::env::current_dir()?;
    let log_path = format!("/tmp/hiboss-daemon-{}.log", session::project_hash());
    // Fork: launch self with `daemon run` in background
    let child = Command::new(&exe)
        .args(["daemon", "run"])
        .current_dir(&cwd)
        .stdout(fs::File::create(&log_path)?)
        .stderr(fs::File::create(&log_path)?)
        .stdin(std::process::Stdio::null())
        .spawn()?;
    let pid = child.id();
    fs::write(session::daemon_pid_path(), pid.to_string())?;
    eprintln!("Daemon started (pid {}, log: {})", pid, log_path);
    Ok(())
}

fn stop_daemon() -> Result<(), Box<dyn Error>> {
    let pid_path = session::daemon_pid_path();
    match session::is_daemon_running() {
        Some(pid) => {
            let _ = Command::new("kill").arg(pid.to_string()).status();
            let _ = fs::remove_file(&pid_path);
            eprintln!("Daemon stopped (pid {})", pid);
        }
        None => {
            let _ = fs::remove_file(&pid_path);
            eprintln!("Daemon not running");
        }
    }
    Ok(())
}

fn show_status() -> Result<(), Box<dyn Error>> {
    match session::is_daemon_running() {
        Some(pid) => {
            let pending = session::daemon_pending_path();
            let count = fs::read_to_string(&pending)
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
    let pending_path = session::daemon_pending_path();
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

        // Process received messages until channel closes (SSE disconnected)
        let path = pending_path.clone();
        while let Some(event) = rx.recv().await {
            if event.event_type == "message" {
                // Spool holds boss/peer message bodies the hook injects into the agent
                // context; create it owner-only so other users can't read or seed it.
                let mut opts = fs::OpenOptions::new();
                opts.create(true).append(true);
                #[cfg(unix)]
                {
                    use std::os::unix::fs::OpenOptionsExt;
                    // Owner-only, and never append through a symlink a co-resident
                    // user planted at this predictable path (O_NOFOLLOW).
                    opts.mode(0o600).custom_flags(libc::O_NOFOLLOW);
                }
                if let Ok(mut f) = opts.open(&path) {
                    let _ = writeln!(f, "{}", event.data);
                }
            }
            backoff = 5;
        }

        eprintln!("SSE stream closed, reconnecting in {}s...", backoff);
        sleep(Duration::from_secs(backoff)).await;
        backoff = (backoff * 2).min(60);
    }
}
