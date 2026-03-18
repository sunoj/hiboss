// Purpose: Join a hiboss server by requesting approval and storing the returned key.
// Exports: InitArgs, run.
// Dependencies: clap, colored, reqwest, serde, crate::config.

use crate::config::{save_config, Config};
use clap::Args;
use colored::Colorize;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::time::{Duration, Instant};

#[derive(Debug, Args)]
pub struct InitArgs {
    #[arg(value_name = "server")]
    pub server: String,
}

#[derive(Serialize)]
struct JoinRequest {
    name: String,
}

#[derive(Deserialize)]
struct JoinResponse {
    status: String,
    request_id: Option<String>,
    poll_token: Option<String>,
    key: Option<String>,
    agent_id: Option<String>,
}

#[derive(Deserialize)]
struct JoinStatusResponse {
    status: String,
    key: Option<String>,
    agent_id: Option<String>,
    name: Option<String>,
}

pub async fn run(args: &InitArgs, config: &mut Config) -> Result<(), Box<dyn Error>> {
    let server = args.server.trim_end_matches('/');
    let client = Client::new();
    let name = detect_name();
    let join = request_join(&client, server, &name).await?;

    if join.status == "approved" {
        let key = join.key.ok_or("Server approved the join request but did not return a key.")?;
        let agent_id = join.agent_id.unwrap_or_default();
        save_init(config, server, &key)?;
        print_success(server, &name, &agent_id);
        return Ok(());
    }

    if join.status != "pending" {
        return Err(format!("Server returned an unknown join status: {}.", join.status).into());
    }

    let request_id = join.request_id.ok_or("Server returned a pending join without a request ID.")?;
    let poll_token = join.poll_token.ok_or("Server returned a pending join without a poll token.")?;
    eprintln!("{} Waiting for boss approval... (request: {})", "⏳".yellow(), shorten_id(&request_id));
    eprintln!("   The boss has been notified on their channel.");
    poll_for_approval(&client, config, server, &name, &poll_token).await
}

async fn request_join(client: &Client, server: &str, name: &str) -> Result<JoinResponse, Box<dyn Error>> {
    let resp = client.post(format!("{server}/api/join")).json(&JoinRequest { name: name.to_string() }).send().await?;
    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        let detail = if body.trim().is_empty() { "Please try again in a moment.".to_string() } else { body };
        return Err(format!("Join request failed ({status}): {detail}").into());
    }
    Ok(resp.json().await?)
}

async fn poll_for_approval(client: &Client, config: &mut Config, server: &str, name: &str, poll_token: &str) -> Result<(), Box<dyn Error>> {
    let poll_url = format!("{server}/api/join/status?token={poll_token}");
    let start = Instant::now();
    let timeout = Duration::from_secs(300);
    let mut polls = 0u32;

    loop {
        tokio::time::sleep(Duration::from_secs(3)).await;
        polls += 1;
        if start.elapsed() > timeout {
            eprintln!("{} Timed out waiting for approval. Ask your boss to approve, then run `hiboss init {server}` again.", "⏱".red());
            return Err("Approval timed out.".into());
        }
        match fetch_join_status(client, &poll_url).await? {
            Some(status) if status.status == "approved" => return finish_approval(config, server, name, status),
            Some(status) if status.status == "rejected" => return Err("Join request rejected by boss.".into()),
            Some(_) | None if polls % 10 == 0 => eprint!("."),
            Some(_) | None => {}
        }
    }
}

async fn fetch_join_status(client: &Client, poll_url: &str) -> Result<Option<JoinStatusResponse>, Box<dyn Error>> {
    let resp = match client.get(poll_url).send().await {
        Ok(resp) => resp,
        Err(_) => return Ok(None),
    };
    if !resp.status().is_success() {
        return Ok(None);
    }
    Ok(resp.json().await.ok())
}

fn finish_approval(config: &mut Config, server: &str, fallback_name: &str, status: JoinStatusResponse) -> Result<(), Box<dyn Error>> {
    let key = status.key.ok_or("Server approved the join request but did not return a key.")?;
    let agent_id = status.agent_id.unwrap_or_default();
    let display_name = status.name.unwrap_or_else(|| fallback_name.to_string());
    save_init(config, server, &key)?;
    eprintln!();
    print_success(server, &display_name, &agent_id);
    Ok(())
}

fn detect_name() -> String {
    for key in ["USER", "HOSTNAME"] {
        if let Ok(value) = std::env::var(key) {
            if !value.is_empty() {
                return value;
            }
        }
    }
    "new-agent".to_string()
}

fn save_init(config: &mut Config, server: &str, key: &str) -> Result<(), Box<dyn Error>> {
    config.server = Some(server.to_string());
    config.key = Some(key.to_string());
    save_config(config)?;
    Ok(())
}

fn print_success(server: &str, name: &str, agent_id: &str) {
    eprintln!("{} Initialized! Server: {}, Agent: {} ({})", "✅".green(), server, name.bold(), shorten_id(agent_id));
    eprintln!("   Run {} to install Claude Code hooks.", "hiboss setup hooks".cyan());
}

fn shorten_id(id: &str) -> &str {
    &id[..8.min(id.len())]
}
