// Purpose: Display boss-originated messages in a colored tabular inbox view.
// Exports: InboxArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config, helpers::{short_id, truncate, color_priority}};
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
    #[arg(long, help = "Mark displayed messages as read (triggers work-started reaction)")]
    pub ack: bool,
}

pub async fn run(args: &InboxArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.list_messages(!args.all, args.all, args.limit, args.priority.as_deref()).await?;
    if args.count {
        println!("{}", response.total);
        return Ok(());
    }
    println!("{:<10} {:<16} {:<12} {:<50} {}", "ID", "Agent", "Priority", "Body", "Time");
    for message in &response.messages {
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
    if args.ack {
        for message in &response.messages {
            let _ = client.update_status(&message.id, "read").await;
        }
    }
    Ok(())
}
