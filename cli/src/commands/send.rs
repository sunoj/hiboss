// Purpose: Handle hiboss send requests (async agent -> boss messages).
// Exports: SendArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body, session, types::SendRequest};
use clap::Args;
use serde_json::Value;
use std::collections::HashMap;
use std::error::Error;

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
    #[arg(long = "type", help = "Message type (e.g. task_update, approval_request)")]
    pub message_type: Option<String>,
    #[arg(long, help = "Target agent name or ID for agent-to-agent messaging")]
    pub to: Option<String>,
    #[arg(long, help = "Broadcast to all active peer sessions on same project")]
    pub broadcast: bool,
    #[arg(long, help = "Task summary for structured context")]
    pub task: Option<String>,
    #[arg(long, help = "Relevant file paths (comma-separated)")]
    pub files: Option<String>,
    #[arg(long, help = "Git branch context")]
    pub branch: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}

pub async fn run(args: &SendArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    if args.broadcast && args.to.is_some() {
        return Err("Cannot use --broadcast and --to together".into());
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
    let response = client.send_message(&request).await?;
    eprintln!("Message sent");
    session::mark_replied();
    println!("{}", response.id);
    Ok(())
}

async fn run_broadcast(args: &SendArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let my_session_id = session::read_session_id().unwrap_or_default();
    let sessions = client.list_sessions().await?;
    let peers: Vec<_> = sessions.sessions.iter()
        .filter(|s| s.id != my_session_id && s.status.as_deref() != Some("completed"))
        .collect();

    if peers.is_empty() {
        eprintln!("No active peer sessions to broadcast to");
        return Ok(());
    }

    let body = unescape_body(&args.body);
    let metadata = build_metadata(args)?;
    let mut sent = 0u32;

    for peer in &peers {
        // Target by session label (repo/branch) or fall back to session ID
        let target = peer.label.as_deref().unwrap_or(&peer.id);
        let request = SendRequest {
            body: body.clone(),
            mode: "async".to_owned(),
            priority: args.priority.clone(),
            channel: None,
            metadata: metadata.clone(),
            options: None,
            file_url: None,
            message_type: args.message_type.clone(),
            session_id: session::read_session_id(),
            to: Some(target.to_owned()),
        };
        match client.send_message(&request).await {
            Ok(_) => sent += 1,
            Err(e) => eprintln!("Failed to send to {}: {}", target, e),
        }
    }

    eprintln!("Broadcast sent to {} peer session(s)", sent);
    session::mark_broadcast();
    session::mark_replied();
    Ok(())
}

fn build_metadata(args: &SendArgs) -> Result<Option<HashMap<String, Value>>, Box<dyn Error>> {
    if args.task.is_some() || args.files.is_some() || args.branch.is_some() {
        let mut ctx = HashMap::new();
        if let Some(ref t) = args.task {
            ctx.insert("summary".to_owned(), Value::String(t.clone()));
        }
        if let Some(ref f) = args.files {
            let files: Vec<Value> = f.split(',').map(|s| Value::String(s.trim().to_owned())).collect();
            ctx.insert("files".to_owned(), Value::Array(files));
        }
        if let Some(ref b) = args.branch {
            ctx.insert("branch".to_owned(), Value::String(b.clone()));
        }
        let mut meta = HashMap::new();
        meta.insert("task_context".to_owned(), serde_json::to_value(ctx)?);
        Ok(Some(meta))
    } else {
        Ok(None)
    }
}
