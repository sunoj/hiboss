// Purpose: Display boss-originated messages in a colored tabular inbox view.
// Exports: InboxArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config, helpers::{short_id, truncate, color_priority}, session};
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
    #[arg(long = "type", help = "Filter by message type (e.g. task_update, approval_request)")]
    pub msg_type: Option<String>,
}

pub async fn run(args: &InboxArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let session_id = session::read_session_id();
    let response = client.list_messages(!args.all, args.all, args.limit, args.priority.as_deref(), args.msg_type.as_deref(), session_id.as_deref()).await?;
    if args.count {
        println!("{}", response.total);
        return Ok(());
    }
    let has_types = response.messages.iter().any(|m| {
        m.message_type.as_deref().map_or(false, |t| t != "text")
    });
    if has_types {
        println!("{:<10} {:<16} {:<12} {:<16} {:<40} {}", "ID", "Agent", "Priority", "Type", "Body", "Time");
    } else {
        println!("{:<10} {:<16} {:<12} {:<50} {}", "ID", "Agent", "Priority", "Body", "Time");
    }
    for message in &response.messages {
        let id = short_id(&message.id);
        let agent = message.agent_name.as_deref().unwrap_or("-");
        let priority = message.priority.as_deref().unwrap_or("normal");
        let priority_display = color_priority(priority);
        let body = message.body.as_deref().unwrap_or("-");
        let time_label = message
            .created_at
            .as_deref()
            .unwrap_or("-")
            .to_string();
        if has_types {
            let msg_type = message.message_type.as_deref().unwrap_or("text");
            let truncated = truncate(body, 37);
            println!("{:<10} {:<16} {:<12} {:<16} {:<40} {}", id, agent.cyan(), priority_display, msg_type, truncated, time_label.dimmed());
        } else {
            let truncated = truncate(body, 47);
            println!("{:<10} {:<16} {:<12} {:<50} {}", id, agent.cyan(), priority_display, truncated, time_label.dimmed());
        }
    }
    if args.ack {
        for message in &response.messages {
            let _ = client.update_status(&message.id, "read").await;
        }
    }
    Ok(())
}
