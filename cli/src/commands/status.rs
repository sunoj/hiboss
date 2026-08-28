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

pub async fn run(
    args: &StatusArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let mut message = client.get_message(&args.id).await?;
    let is_a2a = message.direction.as_deref() == Some("agent_to_agent");
    if !is_a2a {
        if let Err(err) = client.update_status(&args.id, "read").await {
            eprintln!("Could not update status: {}", err);
        }
        message = client.get_message(&args.id).await?;
    }
    println!("ID: {}", message.id);
    let status = message.status.as_deref().unwrap_or("unknown");
    if is_a2a {
        println!("Delivery: {status}");
    } else {
        println!("Status: {status}");
    }
    if let Some(replies) = &message.replies {
        for reply in replies {
            println!(
                "Reply {}: {}",
                reply.id,
                reply.body.as_deref().unwrap_or("-")
            );
        }
    }
    Ok(())
}
