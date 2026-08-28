// Purpose: Handle hiboss send requests (async agent -> boss messages).
// Exports: SendArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{
    client::HiBossClient, config::Config, helpers::{short_id, unescape_body}, session,
    types::SendRequest,
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
    #[arg(long, help = "Wait until peer delivery leaves queued")]
    pub wait_ack: bool,
    #[arg(long, help = "Broadcast to all active peer sessions on same project")]
    pub broadcast: bool,
    #[arg(long, help = "Task summary for structured context")]
    pub task: Option<String>,
    #[arg(long, help = "Short non-sensitive summary shown in private-mode push notifications")]
    pub summary: Option<String>,
    #[arg(long, help = "Extra context shown in the notification (subtitle)")]
    pub content: Option<String>,
    #[arg(long, help = "Relevant file paths (comma-separated)")]
    pub files: Option<String>,
    #[arg(long, help = "Git branch context")]
    pub branch: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}
pub async fn run(
    args: &SendArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
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
    let request = SendRequest {
        body: unescape_body(&args.body),
        mode: "async".to_owned(),
        priority: args.priority.clone(),
        channel,
        metadata,
        options: None,
        file_url,
        message_type: args.message_type.clone(),
        session_id: session::read_session_id(),
        to: args.to.clone(),
    };
    let mut response = client.send_message(&request).await?;
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
        let target = response
            .target
            .as_ref()
            .ok_or("send response did not include resolved target")?;
        println!(
            "{} -> {} ({}) id={}",
            response.status,
            target.label.as_deref().unwrap_or(target.id.as_str()),
            short_id(&target.id),
            response.id
        );
    } else {
        println!("{}", response.id);
    }
    Ok(())
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
        let request = broadcast_request(args, &body, metadata.as_ref(), &peer.id);
        let label = peer.label.as_deref().filter(|label| !label.is_empty());
        let outcome = match client.send_message(&request).await {
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
fn broadcast_request(
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
fn broadcast_result_prefix(label: Option<&str>, id: &str) -> String {
    let resolved_label = label.unwrap_or(id);
    format!("Broadcast target {} ({})", resolved_label, short_id(id))
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
fn build_metadata(args: &SendArgs) -> Result<Option<HashMap<String, Value>>, Box<dyn Error>> {
    let has_context = args.task.is_some() || args.files.is_some() || args.branch.is_some();
    let has_content = args.content.as_ref().is_some_and(|s| !s.is_empty());
    if !has_context && args.summary.is_none() && !has_content {
        return Ok(None);
    }
    let mut meta = HashMap::new();
    if let Some(ref s) = args.summary {
        meta.insert("summary".to_owned(), Value::String(s.clone()));
    }
    if let Some(ref s) = args.content {
        if !s.is_empty() {
            meta.insert("content".to_owned(), Value::String(s.clone()));
        }
    }
    if has_context {
        let mut ctx = HashMap::new();
        if let Some(ref t) = args.task {
            ctx.insert("summary".to_owned(), Value::String(t.clone()));
        }
        if let Some(ref f) = args.files {
            let files: Vec<Value> = f
                .split(',')
                .map(|s| Value::String(s.trim().to_owned()))
                .collect();
            ctx.insert("files".to_owned(), Value::Array(files));
        }
        if let Some(ref b) = args.branch {
            ctx.insert("branch".to_owned(), Value::String(b.clone()));
        }
        meta.insert("task_context".to_owned(), serde_json::to_value(ctx)?);
    }
    Ok(Some(meta))
}
#[cfg(test)]
mod tests {
    use super::*;

    fn args_with_content(content: Option<&str>) -> SendArgs {
        SendArgs {
            priority: "normal".to_owned(),
            channel: None,
            file_url: None,
            file: None,
            message_type: None,
            to: None,
            wait_ack: false,
            broadcast: false,
            task: None,
            summary: None,
            content: content.map(str::to_owned),
            files: None,
            branch: None,
            body: "body".to_owned(),
        }
    }
    #[test]
    fn metadata_includes_content() {
        let metadata = build_metadata(&args_with_content(Some("deploy context")))
            .expect("metadata builds")
            .expect("metadata present");
        assert_eq!(
            metadata.get("content"),
            Some(&Value::String("deploy context".to_owned()))
        );
    }

    #[test]
    fn metadata_omits_empty_content() {
        let metadata = build_metadata(&args_with_content(Some("")))
            .expect("metadata builds");
        assert!(metadata.is_none());
    }

    #[test]
    fn broadcast_result_prefix_names_label_and_short_id() {
        assert_eq!(
            broadcast_result_prefix(Some("smart-router/main"), "aefb4ffd12345678"),
            "Broadcast target smart-router/main (aefb4ffd)"
        );
    }

    #[test]
    fn broadcast_request_targets_peer_session_id() {
        let args = args_with_content(None);
        let request = broadcast_request(&args, "broadcast body", None, "peer-session-id");
        assert_eq!(request.body, "broadcast body");
        assert_eq!(request.to.as_deref(), Some("peer-session-id"));
    }
}
