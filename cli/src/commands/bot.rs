// Purpose: Provide the hiboss bot command that auto-replies with an external handler.
// Exports: BotArgs CLI parser and run() to poll messages and reply.
// Dependencies: clap, tokio, crate::client, crate::config, crate::types, std::collections::HashSet, std::process::Stdio.

use crate::{client::HiBossClient, config::Config, types::Message};
use clap::Args;
use std::{collections::HashSet, error::Error, process::Stdio};
use tokio::{
    io::AsyncWriteExt,
    process::Command as TokioCommand,
    signal,
    time::{interval, Duration},
};

const BOT_POLL_LIMIT: u32 = 20;

#[derive(Debug, Args)]
pub struct BotArgs {
    #[arg(long)]
    pub handler: String,
    #[arg(long, default_value_t = 5)]
    pub interval: u64,
}

pub async fn run(args: &BotArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    eprintln!(
        "Bot mode active. Handler: {} (Ctrl+C to stop)",
        args.handler
    );
    let mut seen = HashSet::new();
    let period = args.interval.max(1);
    let mut ticker = interval(Duration::from_secs(period));
    ticker.tick().await;
    if let Err(err) = poll_messages(&args.handler, client, &mut seen).await {
        eprintln!("Bot poll error: {}", err);
    }

    loop {
        tokio::select! {
            _ = signal::ctrl_c() => {
                eprintln!("Bot mode stopping");
                break;
            }
            _ = ticker.tick() => {
                if let Err(err) = poll_messages(&args.handler, client, &mut seen).await {
                    eprintln!("Bot poll error: {}", err);
                }
            }
        }
    }

    Ok(())
}

async fn poll_messages(
    handler: &str,
    client: &HiBossClient,
    seen: &mut HashSet<String>,
) -> Result<(), Box<dyn Error>> {
    let response = client.list_messages(true, false, BOT_POLL_LIMIT).await?;
    for message in response.messages {
        let id = message.id.clone();
        if !seen.insert(id) {
            continue;
        }
        handle_message(handler, client, &message).await;
    }
    Ok(())
}

async fn handle_message(handler: &str, client: &HiBossClient, message: &Message) {
    let id = &message.id;
    let agent = message.agent_name.as_deref().unwrap_or("hiboss");
    let body = message.body.as_deref().unwrap_or("");
    eprintln!("[recv] {}: {}", agent, body);

    match run_handler(handler, body).await {
        Ok(Some(reply)) => {
            if let Err(err) = client.reply_to(id, &reply).await {
                eprintln!("Failed to reply to {}: {}", short_id(id), err);
            } else {
                eprintln!("[reply] {}", truncate(&reply, 80));
            }
        }
        Ok(None) => {
            eprintln!("Handler produced no reply for {}", short_id(id));
        }
        Err(err) => {
            eprintln!("Handler failed for {}: {}", short_id(id), err);
        }
    }

    if let Err(err) = client.update_status(id, "read").await {
        eprintln!("Failed to mark {} as read: {}", short_id(id), err);
    }
}

async fn run_handler(handler: &str, input: &str) -> Result<Option<String>, Box<dyn Error>> {
    let mut child = TokioCommand::new("sh")
        .arg("-c")
        .arg(handler)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    if let Some(mut stdin) = child.stdin.take() {
        if !input.is_empty() {
            stdin.write_all(input.as_bytes()).await?;
        }
        // Dropping stdin to flush and signal EOF.
    }

    let output = child.wait_with_output().await?;
    if !output.status.success() {
        return Ok(None);
    }

    let reply = String::from_utf8_lossy(&output.stdout).to_string();
    let trimmed = reply.trim_end();
    if trimmed.is_empty() {
        return Ok(None);
    }

    Ok(Some(trimmed.to_string()))
}

fn short_id(value: &str) -> String {
    value.chars().take(8).collect()
}

fn truncate(input: &str, limit: usize) -> String {
    if input.chars().count() <= limit {
        input.to_string()
    } else {
        let truncated: String = input.chars().take(limit - 3).collect();
        format!("{}...", truncated)
    }
}
