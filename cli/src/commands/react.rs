// Purpose: Set a reaction emoji on a boss message (Telegram or Discord).
// Exports: ReactArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::session.

use crate::{client::HiBossClient, config::Config, session};
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
    session::mark_replied();
    Ok(())
}
