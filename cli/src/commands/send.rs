// Purpose: Handle hiboss send requests (async agent -> boss messages).
// Exports: SendArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, types::SendRequest};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct SendArgs {
    #[arg(long, default_value = "normal")]
    pub priority: String,
    #[arg(long)]
    pub channel: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}

pub async fn run(args: &SendArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let channel = args.channel.clone().or_else(|| config.channel.clone());
    let request = SendRequest {
        body: args.body.clone(),
        mode: "async".to_owned(),
        priority: args.priority.clone(),
        channel,
        metadata: None,
        options: None,
    };
    let response = client.send_message(&request).await?;
    eprintln!("Message sent");
    println!("{}", response.id);
    Ok(())
}
