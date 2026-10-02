// Purpose: Report the stored status of a message and its replies without changing it.
// Exports: StatusArgs and run(); one GET, then text or a single JSON document on stdout.
// Dependencies: clap, crate::client, crate::config, status_result.

use super::status_result::StatusReport;
use crate::{client::HiBossClient, config::Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct StatusArgs {
    #[arg(value_name = "id")]
    pub id: String,
    /// Print one JSON document (message_id, direction, status, replies) on stdout
    #[arg(long)]
    pub json: bool,
}

pub async fn run(
    args: &StatusArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let message = client.get_message(&args.id).await?;
    let report = StatusReport::from_message(&message);
    if args.json {
        println!("{}", serde_json::to_string(&report)?);
    } else {
        print!("{}", report.text());
    }
    Ok(())
}
