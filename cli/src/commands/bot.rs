// Purpose: Provide the hiboss bot command that auto-replies with an external handler.
// Exports: BotArgs CLI parser and run() to stream messages via SSE and reply.
// Dependencies: clap, tokio, crate::client, crate::config, crate::types, crate::sse.

use crate::{client::HiBossClient, config::Config, helpers::{short_id, truncate}, sse, types::Message};
use clap::Args;
use std::{error::Error, process::Stdio};
use tokio::{
    io::AsyncWriteExt,
    process::Command as TokioCommand,
    signal,
    time::{Duration, sleep},
};

#[derive(Debug, Args)]
pub struct BotArgs {
    #[arg(long)]
    pub handler: String,
    #[arg(long, default_value_t = 5)]
    pub interval: u64,
}

pub async fn run(args: &BotArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let server = config.require_server()?;
    let key = config.require_key()?;
    eprintln!(
        "Bot mode active. Handler: {} (Ctrl+C to stop)",
        args.handler
    );

    let (tx, mut rx) = tokio::sync::mpsc::channel::<sse::SseEvent>(32);
    let sse_url = format!("{}/api/messages/stream", server);
    let sse_client = reqwest::Client::new();
    let sse_key = key;

    tokio::spawn(async move {
        loop {
            eprintln!("Connecting to SSE stream...");
            if let Err(e) = sse::connect_sse(&sse_client, &sse_url, &sse_key, tx.clone()).await {
                eprintln!("SSE error: {}, reconnecting in 5s...", e);
            } else {
                eprintln!("SSE stream closed, reconnecting in 5s...");
            }
            sleep(Duration::from_secs(5)).await;
        }
    });

    loop {
        tokio::select! {
            _ = signal::ctrl_c() => {
                eprintln!("Bot mode stopping");
                break;
            }
            Some(event) = rx.recv() => {
                if event.event_type == "message" {
                    if let Ok(message) = serde_json::from_str::<Message>(&event.data) {
                        handle_message(&args.handler, client, &message).await;
                    }
                }
            }
        }
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
