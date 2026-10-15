// Purpose: Show a full message with its reply chain and reactions.
// Exports: ReadArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, message_security, types::Message};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ReadArgs {
    #[arg(value_name = "id")]
    pub id: String,
    #[arg(long, help = "Fetch and show reactions from the channel")]
    pub reactions: bool,
}

pub async fn run(
    args: &ReadArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let message = client.get_message(&args.id).await?;
    print_message(&message, 0);
    if args.reactions {
        match client.get_reactions(&args.id).await {
            Ok(resp) if !resp.reactions.is_empty() => {
                println!("Reactions:");
                for r in &resp.reactions {
                    let label = reaction_label(r);
                    println!("  {}", label);
                }
            }
            Ok(_) => println!("Reactions: none"),
            Err(e) => eprintln!("Could not fetch reactions: {}", e),
        }
    }
    Ok(())
}

fn print_message(message: &Message, depth: usize) {
    let indent = "  ".repeat(depth);
    println!("{}ID: {}", indent, message.id);
    println!(
        "{}Direction: {}",
        indent,
        message.direction.as_deref().unwrap_or("-")
    );
    println!(
        "{}Channel: {}",
        indent,
        message.channel.as_deref().unwrap_or("-")
    );
    println!(
        "{}Source: {}",
        indent,
        message_security::assurance_label(message)
    );
    println!(
        "{}Status: {}",
        indent,
        message.status.as_deref().unwrap_or("-")
    );
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

fn reaction_label(reaction: &crate::types::Reaction) -> String {
    let identity = reaction
        .actor
        .as_deref()
        .zip(reaction.actor_id.as_deref())
        .map(|(actor, id)| format!("{actor}: {id}"))
        .or_else(|| reaction.user.clone());
    identity
        .map(|user| format!("{} ({user})", reaction.emoji))
        .or_else(|| {
            reaction
                .count
                .map(|count| format!("{} x{count}", reaction.emoji))
        })
        .unwrap_or_else(|| reaction.emoji.clone())
}

#[cfg(test)]
mod tests {
    use super::reaction_label;

    #[test]
    fn reads_actor_and_legacy_reactions() {
        for (raw, expected) in [
            (
                r#"{"emoji":"+1","actor":"boss","actor_id":"123"}"#,
                "+1 (boss: 123)",
            ),
            (r#"{"emoji":"+1","user":"Alice"}"#, "+1 (Alice)"),
            (r#"{"emoji":"+1","count":2}"#, "+1 x2"),
        ] {
            let reaction = serde_json::from_str(raw).expect("valid reaction");
            assert_eq!(reaction_label(&reaction), expected);
        }
    }
}
