// Forward a stored message to another configured channel.
// Exports the Forward clap args and command runner.
// Depends on client message helpers and clap.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct Forward {
    /// Message ID to forward
    pub id: String,
    /// Target channel
    #[arg(long)]
    pub channel: String,
}

pub async fn run(
    args: &Forward,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let channel = args.channel.trim().to_lowercase();
    if channel != "discord" && channel != "telegram" {
        return Err("channel must be discord or telegram".into());
    }
    let message = client.forward_message(&args.id, &channel).await?;
    println!("Forwarded {}", message.id);
    Ok(())
}
