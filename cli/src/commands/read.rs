// Purpose: Show a full message with its reply chain for detailed inspection.
// Exports: ReadArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, types::Message};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ReadArgs {
    #[arg(value_name = "id")]
    pub id: String,
}

pub async fn run(args: &ReadArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let message = client.get_message(&args.id).await?;
    print_message(&message, 0);
    Ok(())
}

fn print_message(message: &Message, depth: usize) {
    let indent = "  ".repeat(depth);
    println!("{}ID: {}", indent, message.id);
    println!("{}Direction: {}", indent, message.direction.as_deref().unwrap_or("-"));
    println!("{}Channel: {}", indent, message.channel.as_deref().unwrap_or("-"));
    println!("{}Status: {}", indent, message.status.as_deref().unwrap_or("-"));
    let msg_type = message.message_type.as_deref().unwrap_or("text");
    if msg_type != "text" {
        println!("{}Type: {}", indent, msg_type);
    }
    println!("{}Body: {}", indent, message.body.as_deref().unwrap_or("-"));
    if let Some(replies) = &message.replies {
        for reply in replies {
            println!("{}Replies:", indent);
            print_message(reply, depth + 1);
        }
    }
}
