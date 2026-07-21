// Purpose: Post a reply to a specific hiboss message.
// Exports: ReplyArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::session.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body, session};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ReplyArgs {
    #[arg(value_name = "id")]
    pub id: String,
    #[arg(value_name = "body")]
    pub body: String,
}

pub async fn run(
    args: &ReplyArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    // Auto-mark parent message as replied
    let _ = client.update_status(&args.id, "replied").await;
    let response = client
        .reply_to(&args.id, &unescape_body(&args.body))
        .await?;
    eprintln!("Reply posted");
    session::mark_replied();
    println!("{}", response.id);
    Ok(())
}
