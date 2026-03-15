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
}

#[derive(Debug, Args)]
pub struct CreateArgs {
    #[arg(value_name = "name")]
    pub name: String,
}

pub async fn run(command: &AgentCommand, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match command {
        AgentCommand::Create(args) => {
            let resp = client.create_agent(&args.name).await?;
            eprintln!("Agent created: {}", resp.name);
            println!("{}", resp.key);
        }
        AgentCommand::List => {
            let resp = client.list_agents().await?;
            println!("{:<10} {:<20} {:<22} {}", "ID", "Name", "Created", "Last Used");
            for agent in resp.keys {
                let id: String = agent.id.chars().take(8).collect();
                let last = agent.last_used_at.as_deref().unwrap_or("-");
                let created = agent.created_at.as_deref().unwrap_or("-");
                println!("{:<10} {:<20} {:<22} {}", id, agent.name.green(), created.dimmed(), last.dimmed());
            }
        }
    }
    Ok(())
}
