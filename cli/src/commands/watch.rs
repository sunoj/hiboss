// Purpose: Poll hiboss for new messages and surface them with CLI output plus macOS alerts.
// Exports: WatchArgs for CLI parsing and run() for the watch loop.
// Dependencies: clap, tokio, colored, crate::client, crate::config, std::collections::HashSet, std::process::Command.

use crate::{client::HiBossClient, config::Config, types::Message};
use clap::Args;
use colored::Colorize;
use std::{collections::HashSet, error::Error, process::Command};
use tokio::{signal, time::{interval, Duration}};

const POLL_LIMIT: u32 = 20;

#[derive(Debug, Args)]
pub struct WatchArgs {
    #[arg(long, default_value_t = 10)]
    pub interval: u64,
    #[arg(long)]
    pub no_notify: bool,
}

pub async fn run(args: &WatchArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    eprintln!("Watching for new messages... (Ctrl+C to stop)");
    println!("{:<10} {:<16} {:<12} {:<50} {}", "ID", "Agent", "Priority", "Body", "Time");
    let mut seen = HashSet::new();
    let period = args.interval.max(1);
    let mut ticker = interval(Duration::from_secs(period));
    ticker.tick().await;
    poll_messages(client, &mut seen, !args.no_notify).await?;

    loop {
        tokio::select! {
            _ = signal::ctrl_c() => {
                eprintln!("Stopped watching");
                break;
            }
            _ = ticker.tick() => {
                poll_messages(client, &mut seen, !args.no_notify).await?;
            }
        }
    }

    Ok(())
}

async fn poll_messages(client: &HiBossClient, seen: &mut HashSet<String>, notify: bool) -> Result<(), Box<dyn Error>> {
    let response = client.list_messages(true, false, POLL_LIMIT).await?;
    for message in response.messages {
        let id = message.id.clone();
        if !seen.insert(id.clone()) {
            continue;
        }
        print_message(&message);
        if notify {
            trigger_notification(&message, &id);
        }
        if let Err(err) = client.update_status(&id, "read").await {
            eprintln!("Failed to mark {} as read: {}", short_id(&id), err);
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

fn trigger_notification(message: &Message, id: &str) {
    let body = message.body.as_deref().unwrap_or("-");
    let agent = message.agent_name.as_deref().unwrap_or("hiboss");
    let script = format!(
        "display notification \"{}\" with title \"hiboss\" subtitle \"{}\"",
        escape_applescript(body),
        escape_applescript(agent),
    );
    match Command::new("osascript").arg("-e").arg(script).status() {
        Ok(status) => {
            if !status.success() {
                eprintln!("Notification command failed for {}: {}", short_id(id), status);
            }
        }
        Err(err) => {
            eprintln!("Notification failed for {}: {}", short_id(id), err);
        }
    }
}

fn escape_applescript(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}

fn short_id(value: &str) -> String {
    value.chars().take(8).collect()
}

fn color_priority(priority: &str) -> colored::ColoredString {
    match priority {
        "critical" => priority.red().bold(),
        "high" => priority.yellow().bold(),
        "normal" => priority.green(),
        "low" => priority.white(),
        _ => priority.normal(),
    }
}

fn truncate(input: &str, limit: usize) -> String {
    if input.chars().count() <= limit {
        input.to_string()
    } else {
        let truncated: String = input.chars().take(limit - 3).collect();
        format!("{}...", truncated)
    }
}
