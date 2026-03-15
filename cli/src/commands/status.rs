// Purpose: Report the current status of a sent message and any replies.
// Exports: StatusArgs and run().
// Dependencies: clap, crate::client, crate::config.

use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct StatusArgs {
    #[arg(value_name = "id")]
    pub id: String,
}

pub async fn run(args: &StatusArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    if let Err(err) = client.update_status(&args.id, "read").await {
        eprintln!("Could not update status: {}", err);
    }
    let message = client.get_message(&args.id).await?;
    println!("ID: {}", message.id);
    println!("Status: {}", message.status.as_deref().unwrap_or("unknown"));
    if let Some(replies) = &message.replies {
        for reply in replies {
            println!("Reply {}: {}", reply.id, reply.body.as_deref().unwrap_or("-"));
        }
    }
    Ok(())
}
