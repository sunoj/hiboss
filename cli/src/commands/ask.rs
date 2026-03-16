// Purpose: Support blocking hiboss requests where the agent waits for a boss reply.
// Exports: AskArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body, types::SendRequest};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct AskArgs {
    #[arg(long, default_value_t = 300)]
    pub timeout: u32,
    #[arg(long)]
    pub channel: Option<String>,
    #[arg(long, help = "Quick-reply options (comma-separated: A,B,C)")]
    pub options: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}

pub async fn run(args: &AskArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let channel = args.channel.clone().or_else(|| config.channel.clone());
    let options = args.options.as_ref().map(|o| {
        o.split(',').map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).collect::<Vec<_>>()
    }).filter(|v| !v.is_empty());
    let request = SendRequest {
        body: unescape_body(&args.body),
        mode: "blocking".to_owned(),
        priority: "normal".to_owned(),
        channel,
        metadata: None,
        options,
        file_url: None,
    };
    let submission = client.send_message(&request).await?;
    let poll = client.poll_reply(&submission.id, args.timeout).await?;
    if let Some(replies) = &poll.replies {
        if let Some(reply) = replies.first() {
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
