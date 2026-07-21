// Purpose: Display boss-originated messages in a colored tabular inbox view.
// Exports: InboxArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::{
    client::HiBossClient,
    config::Config,
    helpers::{SessionFields, color_priority, group_messages, short_id, truncate},
    session,
};
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
    #[arg(
        long,
        help = "Mark displayed messages as read (triggers work-started reaction)"
    )]
    pub ack: bool,
    #[arg(
        long = "type",
        help = "Filter by message type (e.g. task_update, approval_request)"
    )]
    pub msg_type: Option<String>,
    #[arg(long, help = "Filter by sender agent name or ID")]
    pub from: Option<String>,
    #[arg(
        long,
        help = "Filter by direction (agent_to_boss, boss_to_agent, agent_to_agent)"
    )]
    pub direction: Option<String>,
    #[arg(long, help = "Search message body text")]
    pub search: Option<String>,
}

pub async fn run(
    args: &InboxArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let session_id = session::read_session_id();
    let response = client
        .list_messages(
            !args.all,
            args.all,
            args.limit,
            args.priority.as_deref(),
            args.msg_type.as_deref(),
            session_id.as_deref(),
            args.from.as_deref(),
            args.direction.as_deref(),
            session_id.as_deref(),
            args.search.as_deref(),
        )
        .await?;
    if args.count {
        println!("{}", response.total);
        return Ok(());
    }
    let has_types = response
        .messages
        .iter()
        .any(|m| m.message_type.as_deref().map_or(false, |t| t != "text"));
    print_column_header(has_types);

    let groups = group_messages(&response.messages, |m| SessionFields {
        session_id: m.session_id.as_deref(),
        session_label: m.session_label.as_deref(),
        session_branch: m.session_branch.as_deref(),
        session_status: m.session_status.as_deref(),
        agent_name: m.agent_name.as_deref(),
        created_at: m.created_at.as_deref(),
    });
    for group in &groups {
        print_group_header(
            &group.title,
            group.agent_name,
            group.status,
            group.items.len(),
        );
        for message in &group.items {
            print_message_row(message, has_types);
        }
    }

    let ids_to_mark: Vec<_> = response
        .messages
        .iter()
        .filter(|m| {
            let status = m.status.as_deref().unwrap_or("");
            status == "sent" || status == "delivered"
        })
        .map(|m| m.id.as_str())
        .collect();
    if !ids_to_mark.is_empty() {
        for id in &ids_to_mark {
            let _ = client.update_status(id, "read").await;
        }
        eprintln!("Marked {} message(s) as read", ids_to_mark.len());
    }
    Ok(())
}

fn print_column_header(has_types: bool) {
    if has_types {
        println!(
            "{:<10} {:<22} {:<12} {:<16} {:<40} {}",
            "ID", "From", "Priority", "Type", "Body", "Time"
        );
    } else {
        println!(
            "{:<10} {:<22} {:<12} {:<50} {}",
            "ID", "From", "Priority", "Body", "Time"
        );
    }
}

fn print_group_header(title: &str, agent_name: Option<&str>, status: Option<&str>, count: usize) {
    let marker = "●".cyan().bold();
    let title_part = title.cyan().bold();
    let mut parts: Vec<String> = vec![marker.to_string(), title_part.to_string()];
    if let Some(agent) = agent_name {
        if !agent.is_empty() {
            parts.push(format!("{}", agent.cyan()));
        }
    }
    if let Some(st) = status {
        if !st.is_empty() {
            parts.push(format!("[{}]", st.cyan()));
        }
    }
    parts.push(format!("({})", count).dimmed().to_string());
    println!("{}", parts.join(" "));
}

fn print_message_row(message: &crate::types::Message, has_types: bool) {
    let id = short_id(&message.id);
    let direction = message.direction.as_deref().unwrap_or("");
    let agent = message.agent_name.as_deref().unwrap_or("-");
    let origin_label = if direction == "agent_to_agent" {
        format!("[agent] {}", agent).cyan()
    } else {
        format!("[boss] {}", agent).cyan()
    };
    let priority = message.priority.as_deref().unwrap_or("normal");
    let priority_display = color_priority(priority);
    let body = message.body.as_deref().unwrap_or("-");
    let time_label = message.created_at.as_deref().unwrap_or("-").to_string();
    if has_types {
        let msg_type = message.message_type.as_deref().unwrap_or("text");
        let truncated = truncate(body, 37);
        println!(
            "{:<10} {:<22} {:<12} {:<16} {:<40} {}",
            id,
            origin_label,
            priority_display,
            msg_type,
            truncated,
            time_label.dimmed()
        );
    } else {
        let truncated = truncate(body, 47);
        println!(
            "{:<10} {:<22} {:<12} {:<50} {}",
            id,
            origin_label,
            priority_display,
            truncated,
            time_label.dimmed()
        );
    }
}
