// Purpose: Manage agent identities (create, list).
// Exports: AgentArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::client::HiBossClient;
use crate::config::Config;
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct AgentArgs {
    #[command(subcommand)]
    pub command: AgentCommand,
}

#[derive(Debug, Subcommand)]
pub enum AgentCommand {
    Create(CreateArgs),
    List,
    #[command(about = "View or update agent configuration")]
    Config(AgentConfigArgs),
}

#[derive(Debug, Args)]
pub struct CreateArgs {
    #[arg(value_name = "name")]
    pub name: String,
}

#[derive(Debug, Args)]
pub struct AgentConfigArgs {
    /// Set default priority (critical, high, normal, low)
    #[arg(long = "default-priority")]
    pub default_priority: Option<String>,
    /// Set rate limit (messages per minute, 0 = unlimited)
    #[arg(long = "rate-limit")]
    pub rate_limit: Option<u32>,
}

pub async fn run(command: &AgentCommand, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match command {
        AgentCommand::Create(args) => {
            let resp = client.create_agent(&args.name).await?;
            eprintln!("Agent created: {}", resp.name);
            println!("{}", resp.key);
        }
        AgentCommand::Config(args) => {
            if args.default_priority.is_none() && args.rate_limit.is_none() {
                // Show current config
                let info = client.get_agent_config().await?;
                println!("default_priority: {}", info["default_priority"].as_str().unwrap_or("normal"));
                let rl = match &info["rate_limit"] {
                    serde_json::Value::Number(n) => n.to_string(),
                    _ => "unlimited".to_string(),
                };
                println!("rate_limit: {} msg/min", rl);
            } else {
                let mut updates = serde_json::Map::new();
                if let Some(dp) = &args.default_priority {
                    updates.insert("default_priority".into(), serde_json::Value::String(dp.clone()));
                }
                if let Some(rl) = args.rate_limit {
                    if rl == 0 {
                        updates.insert("rate_limit".into(), serde_json::Value::Null);
                    } else {
                        updates.insert("rate_limit".into(), serde_json::json!(rl));
                    }
                }
                let result = client.update_agent_config(&serde_json::Value::Object(updates)).await?;
                eprintln!("Config updated");
                println!("default_priority: {}", result["default_priority"].as_str().unwrap_or("normal"));
                let rl = match &result["rate_limit"] {
                    serde_json::Value::Number(n) => n.to_string(),
                    _ => "unlimited".to_string(),
                };
                println!("rate_limit: {} msg/min", rl);
            }
        }
        AgentCommand::List => {
            let resp = client.list_agents().await?;
            println!("{:<10} {:<20} {:<10} {:<22} {}", "ID", "Name", "Status", "Created", "Last Seen");
            for agent in resp.keys {
                let id: String = agent.id.chars().take(8).collect();
                let last = agent.last_used_at.as_deref().unwrap_or("-");
                let created = agent.created_at.as_deref().unwrap_or("-");
                let status = agent_status(agent.last_used_at.as_deref());
                println!("{:<10} {:<20} {:<10} {:<22} {}", id, agent.name.green(), status, created.dimmed(), last.dimmed());
            }
        }
    }
    Ok(())
}

fn agent_status(last_used: Option<&str>) -> colored::ColoredString {
    let Some(ts) = last_used else {
        return "offline".red();
    };
    // Parse SQLite datetime: "YYYY-MM-DD HH:MM:SS"
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let parsed = parse_sqlite_datetime(ts).unwrap_or(0);
    let age_secs = now.saturating_sub(parsed);
    if age_secs < 600 {
        "online".green().bold()
    } else if age_secs < 3600 {
        "idle".yellow()
    } else {
        "offline".red()
    }
}

fn parse_sqlite_datetime(s: &str) -> Option<u64> {
    // "YYYY-MM-DD HH:MM:SS" → rough Unix timestamp
    let parts: Vec<&str> = s.split(|c| c == '-' || c == ' ' || c == ':' || c == 'T').collect();
    if parts.len() < 6 { return None; }
    let y: u64 = parts[0].parse().ok()?;
    let m: u64 = parts[1].parse().ok()?;
    let d: u64 = parts[2].parse().ok()?;
    let h: u64 = parts[3].parse().ok()?;
    let min: u64 = parts[4].parse().ok()?;
    let sec: u64 = parts[5].trim_end_matches('Z').parse().ok()?;
    // Approximate: days since epoch (good enough for online/offline)
    let days = (y - 1970) * 365 + (y - 1969) / 4 + month_days(m, y) + d - 1;
    Some(days * 86400 + h * 3600 + min * 60 + sec)
}

fn month_days(month: u64, year: u64) -> u64 {
    const DAYS: [u64; 12] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    let base = if month > 0 && month <= 12 { DAYS[(month - 1) as usize] } else { 0 };
    if month > 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) { base + 1 } else { base }
}
