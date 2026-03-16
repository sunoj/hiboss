// Purpose: Set a Telegram reaction emoji on a boss message.
// Exports: ReactArgs and run().
// Dependencies: clap, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ReactArgs {
    /// Message ID to react to
    #[arg(value_name = "id")]
    pub id: String,
    /// Emoji to set as reaction
    #[arg(value_name = "emoji")]
    pub emoji: String,
}

pub async fn run(args: &ReactArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.react(&args.id, &args.emoji).await?;
    eprintln!("Reaction set");
    Ok(())
}
