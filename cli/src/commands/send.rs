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
    let metadata = if args.task.is_some() || args.files.is_some() || args.branch.is_some() {
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
        Some(meta)
    } else {
        None
    };
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
    println!("{}", response.id);
    Ok(())
}
