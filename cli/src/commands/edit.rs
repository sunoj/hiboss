// Edit a previously sent message body.
// Exports the Edit command struct and run function.
// Depends on client module for HTTP PATCH.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct Edit {
    /// Message ID (or prefix)
    pub id: String,
    /// New message body
    pub body: String,
}

pub async fn run(args: &Edit, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let message = client.edit_message_body(&args.id, &unescape_body(&args.body)).await?;
    println!("Edited {}", message.id);
    Ok(())
}
