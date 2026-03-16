// Purpose: Stream hiboss messages in real-time via SSE with CLI output and macOS alerts.
// Exports: WatchArgs for CLI parsing and run() for the SSE watch loop.
// Dependencies: clap, tokio, colored, crate::client, crate::config, crate::sse, std::process::Command.

use crate::{client::HiBossClient, config::Config, helpers::{short_id, truncate, color_priority}, sse, types::Message};
use clap::Args;
use colored::Colorize;
use std::{error::Error, process::Command};
use tokio::{signal, time::{Duration, sleep}};

#[derive(Debug, Args)]
pub struct WatchArgs {
    #[arg(long, default_value_t = 10)]
    pub interval: u64,
    #[arg(long)]
    pub no_notify: bool,
}

pub async fn run(args: &WatchArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let server = config.require_server()?;
    let key = config.require_key()?;
    let notify = !args.no_notify;
    eprintln!("Watching for new messages... (Ctrl+C to stop)");
    println!("{:<10} {:<16} {:<12} {:<50} {}", "ID", "Agent", "Priority", "Body", "Time");

    let (tx, mut rx) = tokio::sync::mpsc::channel::<sse::SseEvent>(32);
    let sse_url = format!("{}/api/messages/stream", server);
    let sse_client = reqwest::Client::new();
    let sse_key = key;

    tokio::spawn(async move {
        let mut backoff = 5u64;
        loop {
            eprintln!("Connecting to SSE stream...");
            match sse::connect_sse(&sse_client, &sse_url, &sse_key, tx.clone()).await {
                Err(e) => eprintln!("SSE error: {}, retrying in {}s...", e, backoff),
                Ok(_) => {
                    backoff = 5; // Reset on clean disconnect
                    eprintln!("SSE stream closed, reconnecting in 5s...");
                }
            }
            sleep(Duration::from_secs(backoff)).await;
            backoff = (backoff * 2).min(60); // Cap at 60s
        }
    });

    loop {
        tokio::select! {
            _ = signal::ctrl_c() => {
                eprintln!("Stopped watching");
                break;
            }
            Some(event) = rx.recv() => {
                if event.event_type == "message" {
                    if let Ok(message) = serde_json::from_str::<Message>(&event.data) {
                        print_message(&message);
                        if notify {
                            trigger_notification(&message);
                        }
                        let _ = client.update_status(&message.id, "read").await;
                    }
                }
            }
        }
    }

    Ok(())
}

fn print_message(message: &Message) {
    let id = short_id(&message.id);
    let agent = message.agent_name.as_deref().unwrap_or("-");
    let priority = message.priority.as_deref().unwrap_or("normal");
    let priority_display = color_priority(priority);
    let body = message.body.as_deref().unwrap_or("-");
    let truncated = truncate(body, 47);
    let time_label = message.created_at.as_deref().unwrap_or("-");
    println!("{:<10} {:<16} {:<12} {:<50} {}", id, agent.cyan(), priority_display, truncated, time_label.dimmed());
}

fn trigger_notification(message: &Message) {
    let body = message.body.as_deref().unwrap_or("-");
    let agent = message.agent_name.as_deref().unwrap_or("hiboss");
    let script = format!(
        "display notification \"{}\" with title \"hiboss\" subtitle \"{}\"",
        escape_applescript(body),
        escape_applescript(agent),
    );
    let _ = Command::new("osascript").arg("-e").arg(script).status();
}

fn escape_applescript(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}
