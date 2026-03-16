// Purpose: Manage routing rules via the hiboss CLI.
// Exports: RouteArgs, RouteCommand, and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::client::HiBossClient;
use crate::config::Config;
use crate::helpers::short_id;
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct RouteArgs {
    #[command(subcommand)]
    pub command: RouteCommand,
}

#[derive(Debug, Subcommand)]
pub enum RouteCommand {
    /// List routing rules
    List,
    /// Add a routing rule
    Add(RouteAddArgs),
    /// Remove a routing rule
    Remove(RouteRemoveArgs),
}

#[derive(Debug, Args)]
pub struct RouteAddArgs {
    /// Channel to match (telegram, discord)
    #[arg(long)]
    pub channel: String,
    /// Regex pattern to match message body
    #[arg(long)]
    pub pattern: String,
    /// Target agent ID to route matching messages to
    #[arg(long)]
    pub target: String,
    /// Rule priority (higher = evaluated first)
    #[arg(long, default_value = "0")]
    pub priority: i32,
}

#[derive(Debug, Args)]
pub struct RouteRemoveArgs {
    /// Rule ID to remove
    pub id: String,
}

pub async fn run(args: &RouteArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        RouteCommand::List => run_list(client).await,
        RouteCommand::Add(add_args) => run_add(add_args, client).await,
        RouteCommand::Remove(rm_args) => run_remove(rm_args, client).await,
    }
}

async fn run_list(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let rules = client.list_routing_rules().await?;
    let items = rules["rules"].as_array();
    if items.map_or(true, |a| a.is_empty()) {
        eprintln!("No routing rules configured.");
        return Ok(());
    }
    println!("{:<10} {:<10} {:<20} {:<10} {:<8}", "ID", "Channel", "Pattern", "Target", "Priority");
    for rule in items.unwrap() {
        let id = short_id(rule["id"].as_str().unwrap_or(""));
        let ch = rule["channel"].as_str().unwrap_or("-");
        let pat = rule["pattern"].as_str().unwrap_or("-");
        let target = short_id(rule["target_agent_id"].as_str().unwrap_or(""));
        let pri = rule["priority"].as_i64().unwrap_or(0);
        println!("{:<10} {:<10} {:<20} {:<10} {:<8}", id.green(), ch, pat.dimmed(), target, pri);
    }
    Ok(())
}

async fn run_add(args: &RouteAddArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let rule = client
        .create_routing_rule(&args.channel, &args.pattern, &args.target, args.priority)
        .await?;
    let id = rule["id"].as_str().unwrap_or("unknown");
    eprintln!("Rule created: {}", short_id(id));
    Ok(())
}

async fn run_remove(args: &RouteRemoveArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.delete_routing_rule(&args.id).await?;
    eprintln!("Rule deleted");
    Ok(())
}
