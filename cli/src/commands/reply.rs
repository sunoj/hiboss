// Purpose: Post a reply to a specific hiboss message.
// Exports: ReplyArgs and run().
// Dependencies: clap, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ReplyArgs {
    #[arg(value_name = "id")]
    pub id: String,
    #[arg(value_name = "body")]
    pub body: String,
}

pub async fn run(args: &ReplyArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.reply_to(&args.id, &args.body).await?;
    eprintln!("Reply posted");
    println!("{}", response.id);
    Ok(())
}
