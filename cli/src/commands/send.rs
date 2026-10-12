// Purpose: Handle hiboss send requests (async agent -> boss messages).
// Exports: SendArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use super::send_metadata::build_metadata;
use super::session_register::send_with_session_heal;
use crate::{
    client::HiBossClient,
    config::Config,
    helpers::{short_id, unescape_body},
    session,
    types::{SendRequest, SendTarget},
};
use clap::Args;
use colored::Colorize;
use serde_json::Value;
use std::{collections::HashMap, error::Error, time::Duration};

#[derive(Debug, Args)]
pub struct SendArgs {
    #[arg(long, short = 'p', default_value = "normal")]
    pub priority: String,
    #[arg(long, help = "Override channel (skips server-side channel_routing)")]
    pub channel: Option<String>,
    #[arg(long, help = "URL of file/image to attach")]
    pub file_url: Option<String>,
    #[arg(long, help = "Local file to upload and attach")]
    pub file: Option<String>,
    #[arg(
        long = "type",
        help = "Message type (e.g. task_update, approval_request)"
    )]
    pub message_type: Option<String>,
    #[arg(long, help = "Target agent name or ID for agent-to-agent messaging")]
    pub to: Option<String>,
    #[arg(long, help = "Wait until peer delivery leaves sent")]
    pub wait_ack: bool,
    #[arg(long, help = "Broadcast to all active peer sessions on same project")]
    pub broadcast: bool,
    #[arg(long, help = "Task summary for structured context")]
    pub task: Option<String>,
    #[arg(
        long,
        help = "Short non-sensitive summary shown in private-mode push notifications"
    )]
    pub summary: Option<String>,
    #[arg(
        long,
        conflicts_with = "content_file",
        help = "Markdown message details beneath the short title"
    )]
    pub content: Option<String>,
    #[arg(
        long,
        conflicts_with = "content",
        help = "UTF-8 Markdown file containing the complete message details"
    )]
    pub content_file: Option<std::path::PathBuf>,
    #[arg(long, help = "Relevant file paths (comma-separated)")]
    pub files: Option<String>,
    #[arg(long, help = "Git branch context")]
    pub branch: Option<String>,
    #[arg(
        value_name = "title",
        help = "Short title, at most 144 Unicode characters"
    )]
    pub body: String,
}

pub async fn run(
    args: &SendArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    super::claude_profiles::warn_missing_session(session::read_session_id().as_deref());
    super::message_text::title(&args.body, args.to.is_some() || args.broadcast)?;
    build_metadata(args)?;
    if args.broadcast && args.to.is_some() {
        return Err("Cannot use --broadcast and --to together".into());
    }

    if args.wait_ack && args.to.is_none() {
        return Err("--wait-ack requires --to".into());
    }

    // Read-before-write: check for unread messages before sending (skip for broadcasts/a2a)
    if args.to.is_none() && !args.broadcast {
        warn_unread_messages(client).await;
    }

    // Handle broadcast: send to all active peer sessions
    if args.broadcast {
        return run_broadcast(args, client).await;
    }

    let mut request = send_request(args, client).await?;
    let mut response = send_with_session_heal(client, &mut request).await?;
    if args.wait_ack {
        response.status = client
            .wait_for_delivery(&response.id, Duration::from_secs(30))
            .await?;
    }
    eprintln!("Message sent");
    if let Some(warning) = &response.warning {
        eprintln!("{}", format!("Warning: {warning}").yellow());
    }
    session::mark_replied();
    if args.to.is_some() {
        println!(
            "{} -> {} id={}",
            response.status,
            format_peer_target(response.target.as_ref(), args.to.as_deref().unwrap_or("")),
            response.id
        );
    } else {
        println!("{}", response.id);
    }
    Ok(())
}

async fn send_request(
    args: &SendArgs,
    client: &HiBossClient,
) -> Result<SendRequest, Box<dyn Error>> {
    // Only send channel when explicitly specified via --channel.
    // When omitted, server uses channel_routing (per-priority) to decide.
    let channel = args.channel.clone();
    let file_url = if let Some(ref path) = args.file {
        let upload = client.upload_file(path).await?;
        eprintln!("Uploaded: {} ({})", upload.filename, upload.url);
        Some(upload.url)
    } else {
        args.file_url.clone()
    };
    // Build task_context metadata from --task, --files, --branch flags
    let metadata = build_metadata(args)?;
    Ok(SendRequest {
        body: super::message_text::title(&args.body, args.to.is_some())?,
        mode: "async".to_owned(),
        timeout: None,
        priority: args.priority.clone(),
        channel,
        metadata,
        options: None,
        file_url,
        message_type: args.message_type.clone(),
        session_id: session::read_session_id(),
        to: args.to.clone(),
    })
}

async fn run_broadcast(args: &SendArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let my_session_id = session::read_session_id().unwrap_or_default();
    let sessions = client.list_sessions().await?;
    let peers: Vec<_> = sessions
        .sessions
        .iter()
        .filter(|s| s.id != my_session_id && s.status.as_deref() != Some("completed"))
        .collect();

    if peers.is_empty() {
        println!("No active peer sessions to broadcast to");
        return Ok(());
    }

    let body = unescape_body(&args.body);
    let metadata = build_metadata(args)?;
    let mut sent = 0u32;
    let mut failures = 0u32;

    for peer in &peers {
        let mut request = broadcast_request(args, &body, metadata.as_ref(), &peer.id);
        let label = peer.label.as_deref().filter(|label| !label.is_empty());
        let outcome = match send_with_session_heal(client, &mut request).await {
            Ok(_) => {
                sent += 1;
                "succeeded".to_owned()
            }
            Err(e) => {
                failures += 1;
                format!("failed: {e}")
            }
        };
        println!("{}: {outcome}", broadcast_result_prefix(label, &peer.id));
    }

    println!("Broadcast sent to {} peer session(s)", sent);
    if failures > 0 {
        return Err(format!(
            "Broadcast failed: {} of {} peer session(s) failed",
            failures,
            peers.len()
        )
        .into());
    }
    session::mark_broadcast();
    session::mark_replied();
    Ok(())
}

pub(crate) fn broadcast_request(
    args: &SendArgs,
    body: &str,
    metadata: Option<&HashMap<String, Value>>,
    peer_id: &str,
) -> SendRequest {
    // Target by exact session ID — labels (repo/branch) collide across sessions and the
    // server resolves a colliding label to the newest same-label session (often self).
    SendRequest {
        body: body.to_owned(),
        mode: "async".to_owned(),
        timeout: None,
        priority: args.priority.clone(),
        channel: None,
        metadata: metadata.cloned(),
        options: None,
        file_url: None,
        message_type: args.message_type.clone(),
        session_id: session::read_session_id(),
        to: Some(peer_id.to_owned()),
    }
}

pub(crate) fn broadcast_result_prefix(label: Option<&str>, id: &str) -> String {
    let resolved_label = label.unwrap_or(id);
    format!("Broadcast target {} ({})", resolved_label, short_id(id))
}

pub(crate) fn format_peer_target(target: Option<&SendTarget>, requested: &str) -> String {
    target
        .map(|target| {
            format!(
                "{} ({})",
                target
                    .nickname
                    .as_deref()
                    .or(target.label.as_deref())
                    .unwrap_or(target.id.as_str()),
                short_id(&target.id)
            )
        })
        .unwrap_or_else(|| requested.to_owned())
}

/// Check for unread boss messages before sending. Warns via stdout so the AI sees it.
async fn warn_unread_messages(client: &HiBossClient) {
    let sid = crate::session::read_session_id();
    let boss_count = client.inbox_count(None, sid.as_deref()).await.unwrap_or(0);
    let a2a_count = client.inbox_count_a2a(sid.as_deref()).await.unwrap_or(0);
    if boss_count > 0 || a2a_count > 0 {
        if boss_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread boss message(s). Read them FIRST: hiboss inbox",
                boss_count
            );
        }
        if a2a_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread peer message(s). Read them FIRST: hiboss inbox --direction agent_to_agent",
                a2a_count
            );
        }
        println!(
            "Reply to unread messages with: hiboss reply <id> \"response\" BEFORE sending new messages."
        );
    }
}
