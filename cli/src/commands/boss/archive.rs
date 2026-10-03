// Reversible boss archive commands and list date presentation.
// Exports run and archived_date; depends on HiBossClient, JSON, and Write.
use crate::client::HiBossClient;
use serde_json::Value;
use std::{error::Error, io::Write};

pub async fn run(client: &HiBossClient, id: &str, archive: bool, output: &mut impl Write) -> Result<(), Box<dyn Error>> {
    if archive { client.archive_boss(id).await?; } else { client.restore_boss(id).await?; }
    writeln!(output, "Boss {}", if archive { "archived" } else { "restored" })?;
    Ok(())
}

pub fn archived_date(boss: &Value) -> &str {
    boss["archived_at"].as_str().and_then(|value| value.split(' ').next()).unwrap_or("-")
}

#[cfg(test)]
#[path = "archive_tests.rs"]
mod tests;
