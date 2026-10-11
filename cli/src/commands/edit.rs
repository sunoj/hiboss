// Edit a previously sent message body.
// Exports the Edit command struct and run function.
// Depends on client module for HTTP PATCH.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct Edit {
    /// Message ID (or prefix)
    pub id: String,
    /// New short title, at most 144 Unicode characters
    pub body: String,
}

pub async fn run(
    args: &Edit,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let message = client
        .edit_message_body(&args.id, &super::message_text::title(&args.body, false)?)
        .await?;
    println!("Edited {}", message.id);
    Ok(())
}
