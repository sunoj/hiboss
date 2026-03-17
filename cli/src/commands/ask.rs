// Purpose: Support blocking hiboss requests where the agent waits for a boss reply.
// Exports: AskArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body, session, types::SendRequest};
use clap::Args;
use serde_json::Value;
use std::collections::HashMap;
use std::error::Error;

#[derive(Debug, Args)]
pub struct AskArgs {
    #[arg(long, default_value_t = 300)]
    pub timeout: u32,
    #[arg(long, help = "Override channel (skips server-side channel_routing)")]
    pub channel: Option<String>,
    #[arg(long, help = "Quick-reply options (comma-separated: A,B,C)")]
    pub options: Option<String>,
    #[arg(long, help = "Action buttons (Label:command pairs, comma-separated: Approve:aid merge t-1,Reject)")]
    pub actions: Option<String>,
    #[arg(long, help = "Local file to upload and attach")]
    pub file: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}

/// Parse --actions "Approve:aid merge t-1,Reject" into (options, actions_map).
/// Labels without a command just become options with no action.
fn parse_actions(raw: &str) -> (Vec<String>, HashMap<String, Value>) {
    let mut options = Vec::new();
    let mut actions = HashMap::new();
    for part in raw.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some(idx) = part.find(':') {
            let label = part[..idx].trim().to_owned();
            let command = part[idx + 1..].trim().to_owned();
            if !label.is_empty() {
                options.push(label.clone());
                if !command.is_empty() {
                    actions.insert(label, Value::String(command));
                }
            }
        } else {
            options.push(part.to_owned());
        }
    }
    (options, actions)
}

fn tail_lines(s: &str, n: usize) -> String {
    let lines: Vec<&str> = s.trim().lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].join("\n")
}

pub async fn run(args: &AskArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    // Only send channel when explicitly specified via --channel.
    // When omitted, server uses channel_routing (per-priority) to decide.
    let channel = args.channel.clone();
    let mut metadata: Option<HashMap<String, Value>> = None;

    // Parse --actions or --options
    let options = if let Some(ref actions_str) = args.actions {
        let (opts, actions_map) = parse_actions(actions_str);
        if !actions_map.is_empty() {
            let mut meta = HashMap::new();
            meta.insert("actions".to_owned(), serde_json::to_value(&actions_map)?);
            metadata = Some(meta);
        }
        if opts.is_empty() { None } else { Some(opts) }
    } else {
        args.options.as_ref().map(|o| {
            o.split(',').map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).collect::<Vec<_>>()
        }).filter(|v| !v.is_empty())
    };

    let file_url = if let Some(ref path) = args.file {
        let upload = client.upload_file(path).await?;
        eprintln!("Uploaded: {} ({})", upload.filename, upload.url);
        Some(upload.url)
    } else {
        None
    };

    let request = SendRequest {
        body: unescape_body(&args.body),
        mode: "blocking".to_owned(),
        priority: "normal".to_owned(),
        channel,
        metadata,
        options,
        file_url,
        message_type: None,
        session_id: session::read_session_id(),
    };
    let submission = client.send_message(&request).await?;
    let poll = client.poll_reply(&submission.id, args.timeout).await?;
    if let Some(replies) = &poll.replies {
        if let Some(reply) = replies.first() {
            // Check for action in reply metadata and auto-execute
            if let Some(meta) = &reply.metadata {
                if let Some(Value::String(action_cmd)) = meta.get("action") {
                    if let Some(body) = &reply.body {
                        println!("{}", body);
                    }
                    eprintln!("Executing action: {}", action_cmd);
                    let output = std::process::Command::new("sh")
                        .arg("-c")
                        .arg(action_cmd)
                        .output();
                    let feedback = match &output {
                        Ok(o) if o.status.success() => {
                            let stdout = String::from_utf8_lossy(&o.stdout);
                            let tail = tail_lines(&stdout, 5);
                            if tail.is_empty() {
                                format!("✅ `{}` succeeded", action_cmd)
                            } else {
                                format!("✅ `{}` succeeded:\n{}", action_cmd, tail)
                            }
                        }
                        Ok(o) => {
                            let stderr = String::from_utf8_lossy(&o.stderr);
                            let tail = tail_lines(&stderr, 5);
                            format!("❌ `{}` failed (exit {}):\n{}", action_cmd, o.status, tail)
                        }
                        Err(e) => format!("❌ `{}` failed: {}", action_cmd, e),
                    };
                    eprintln!("{}", feedback);
                    // Best-effort: send result back to boss
                    let _ = client.send_message(&SendRequest {
                        body: feedback,
                        mode: "async".to_owned(),
                        priority: "normal".to_owned(),
                        channel: None,
                        metadata: None,
                        options: None,
                        file_url: None,
                        message_type: Some("action_result".to_owned()),
                        session_id: session::read_session_id(),
                    }).await;
                    return Ok(());
                }
            }
            if let Some(body) = &reply.body {
                println!("{}", body);
                return Ok(());
            }
        }
    }
    eprintln!("No reply yet");
    println!("{}", submission.id);
    Ok(())
}
