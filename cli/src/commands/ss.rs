// Purpose: Session status board and manual status control.
// Exports: SsArgs, SsCommand, run().
// Dependencies: clap, crate::client, crate::config, crate::session, colored.

use crate::{client::HiBossClient, config::Config, session};
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

const VALID_STATUSES: &[&str] = &["working", "blocked", "waiting", "idle", "completed"];

#[derive(Debug, Args)]
pub struct SsArgs {
    #[command(subcommand)]
    pub command: Option<SsCommand>,
}

#[derive(Debug, Subcommand)]
pub enum SsCommand {
    #[command(about = "Set current session status")]
    Set(SetStatusArgs),
}

#[derive(Debug, Args)]
pub struct SetStatusArgs {
    #[arg(help = "Status: working, blocked, waiting, idle, completed")]
    pub status: String,
    #[arg(help = "Optional status description")]
    pub text: Option<String>,
}

pub async fn run(args: &SsArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        Some(SsCommand::Set(set_args)) => run_set(set_args, client).await,
        None => run_board(client).await,
    }
}

async fn run_set(args: &SetStatusArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let status = args.status.to_lowercase();
    if !VALID_STATUSES.contains(&status.as_str()) {
        return Err(format!("Invalid status '{}'. Must be one of: {}", status, VALID_STATUSES.join(", ")).into());
    }
    let sid = session::read_session_id()
        .ok_or("No active session. Run hiboss hook session-start first.")?;
    client.heartbeat_session(&sid, Some(&status), args.text.as_deref()).await?;
    let icon = match status.as_str() {
        "working" => "🔨",
        "blocked" => "🚫",
        "waiting" => "⏳",
        "idle" => "💤",
        "completed" => "✅",
        _ => "•",
    };
    let text = args.text.as_deref().unwrap_or("");
    if text.is_empty() {
        println!("{} Status set to {}", icon, status);
    } else {
        println!("{} Status set to {}: {}", icon, status, text);
    }
    Ok(())
}

async fn run_board(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let resp = client.list_sessions().await?;
    let sessions = resp.sessions;
    if sessions.is_empty() {
        println!("{}", "No active sessions".dimmed());
        return Ok(());
    }
    let statuses = ["working", "blocked", "waiting", "idle", "completed"];
    let icons = ["🔨", "🚫", "⏳", "💤", "✅"];
    let colors: Vec<Box<dyn Fn(&str) -> colored::ColoredString>> = vec![
        Box::new(|s: &str| s.green()),
        Box::new(|s: &str| s.red()),
        Box::new(|s: &str| s.yellow()),
        Box::new(|s: &str| s.dimmed()),
        Box::new(|s: &str| s.blue()),
    ];
    for (i, status) in statuses.iter().enumerate() {
        let group: Vec<_> = sessions.iter()
            .filter(|s| s.status.as_deref().unwrap_or("working") == *status)
            .collect();
        if group.is_empty() { continue; }
        println!("{} {} ({})", icons[i], colors[i](status), group.len());
        for s in &group {
            let id_short: String = s.id.chars().take(8).collect();
            let label = s.label.as_deref().unwrap_or("-");
            let agent = s.agent_name.as_deref().unwrap_or(&s.agent_id);
            let text = s.status_text.as_deref().unwrap_or("");
            let text_display = if text.chars().count() > 60 {
                format!("{}...", text.chars().take(57).collect::<String>())
            } else { text.to_string() };
            println!("  {} {} ({}) {}", id_short.dimmed(), label, agent.dimmed(), text_display.dimmed());
        }
    }
    Ok(())
}
