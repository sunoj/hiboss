// Purpose: Display boss-originated messages in a colored tabular inbox view.
// Exports: InboxArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct InboxArgs {
    #[arg(long)]
    pub all: bool,
    #[arg(long, default_value_t = 20)]
    pub limit: u32,
    #[arg(long, help = "Filter by priority (comma-separated: critical,high)")]
    pub priority: Option<String>,
    #[arg(long, help = "Print only the message count")]
    pub count: bool,
}

pub async fn run(args: &InboxArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.list_messages(!args.all, args.all, args.limit, args.priority.as_deref()).await?;
    if args.count {
        println!("{}", response.total);
        return Ok(());
    }
    println!("{:<10} {:<16} {:<12} {:<50} {}", "ID", "Agent", "Priority", "Body", "Time");
    for message in response.messages {
        let id = short_id(&message.id);
        let agent = message.agent_name.as_deref().unwrap_or("-");
        let priority = message.priority.as_deref().unwrap_or("normal");
        let priority_display = color_priority(priority);
        let body = message.body.as_deref().unwrap_or("-");
        let truncated = truncate(body, 47);
        let time_label = message
            .created_at
            .as_deref()
            .unwrap_or("-")
            .to_string();
        println!("{:<10} {:<16} {:<12} {:<50} {}", id, agent.cyan(), priority_display, truncated, time_label.dimmed());
    }
    Ok(())
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
