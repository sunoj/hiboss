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
            for agent in resp.agents {
                let id: String = agent.id.chars().take(8).collect();
                let last = agent.last_used_at.as_deref().unwrap_or("-");
                let created = agent.created_at.as_deref().unwrap_or("-");
                let status_str = agent.status.as_deref().unwrap_or("offline");
                let colored_status = match status_str {
                    "online" => status_str.green().bold(),
                    "idle" => status_str.yellow().normal(),
                    _ => status_str.red().normal(),
                };
                println!("{:<10} {:<20} {:<10} {:<22} {}", id, agent.name.green(), colored_status, created.dimmed(), last.dimmed());
            }
        }
    }
    Ok(())
}

