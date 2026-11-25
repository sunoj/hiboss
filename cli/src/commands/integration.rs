// Purpose: Manage Discord-compatible webhook integrations with an admin agent credential.
// Exports: IntegrationCommand and run(); the webhook URL is printed once, on stdout.
// Dependencies: clap, colored, crate::client, crate::commands::SubcommandArgs.

use crate::client::HiBossClient;
use crate::commands::SubcommandArgs;
use clap::{Args, Subcommand, ValueEnum};
use colored::Colorize;
use serde_json::Value;
use std::error::Error;

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum Priority {
    Low,
    Normal,
    High,
}

impl Priority {
    fn as_str(self) -> &'static str {
        match self {
            Priority::Low => "low",
            Priority::Normal => "normal",
            Priority::High => "high",
        }
    }
}

#[derive(Debug, Subcommand)]
pub enum IntegrationCommand {
    /// Create an integration and its first webhook URL (Discord Execute Webhook compatible)
    Create(CreateArgs),
    /// List integrations and their webhook URLs (never the tokens)
    List,
    /// Add another webhook URL to an existing integration
    AddUrl(AddUrlArgs),
    /// Replace a webhook URL's token; the old URL stops working at once
    Rotate(WebhookIdArgs),
    /// Revoke a webhook URL
    Revoke(WebhookIdArgs),
}

#[derive(Debug, Args)]
pub struct CreateArgs {
    /// Name shown as the sender in the apps, e.g. "Grafana prod"
    pub name: String,
    /// Priority of messages from this URL; a post with SUPPRESS_NOTIFICATIONS is always low
    #[arg(long, value_enum, default_value = "normal")]
    pub priority: Priority,
}

#[derive(Debug, Args)]
pub struct AddUrlArgs {
    /// Integration agent ID (from `hiboss integration list`)
    pub agent_id: String,
    /// Label for this URL, e.g. "staging"
    pub label: String,
    #[arg(long, value_enum, default_value = "normal")]
    pub priority: Priority,
}

#[derive(Debug, Args)]
pub struct WebhookIdArgs {
    /// Webhook ID (the digits in the URL)
    pub id: String,
}

pub async fn run(
    args: &SubcommandArgs<IntegrationCommand>,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        IntegrationCommand::Create(a) => {
            let created = client.create_integration(&a.name, a.priority.as_str()).await?;
            eprintln!("Integration created: {} ({})", a.name, created["agent_id"].as_str().unwrap_or("-"));
            print_url(&created["webhook"]);
        }
        IntegrationCommand::List => print_list(&client.list_integrations().await?),
        IntegrationCommand::AddUrl(a) => {
            print_url(&client.add_webhook(&a.agent_id, &a.label, a.priority.as_str()).await?);
        }
        IntegrationCommand::Rotate(a) => print_url(&client.rotate_webhook(&a.id).await?),
        IntegrationCommand::Revoke(a) => {
            client.revoke_webhook(&a.id).await?;
            eprintln!("Webhook {} revoked", a.id);
        }
    }
    Ok(())
}

/// The URL is the credential: it is shown once and only on stdout, so it can be piped.
fn print_url(webhook: &Value) {
    eprintln!(
        "{}",
        "Store this URL like a password; it is shown only once. Use it as a Discord webhook URL.".yellow()
    );
    println!("{}", webhook["url"].as_str().unwrap_or(""));
}

fn print_list(response: &Value) {
    let rows = response["webhooks"].as_array().cloned().unwrap_or_default();
    if rows.is_empty() {
        eprintln!("No integrations found.");
        return;
    }
    println!("{:<20} {:<22} {:<16} {:<8} {}", "Webhook", "Integration", "Label", "Priority", "Last used");
    for row in rows {
        let text = |key: &str| row[key].as_str().unwrap_or("-").to_owned();
        let state = if row["revoked_at"].is_null() { text("last_used_at") } else { "revoked".into() };
        println!(
            "{:<20} {:<22} {:<16} {:<8} {}",
            text("id").green(),
            text("agent_name"),
            text("label"),
            text("priority_cap"),
            state.dimmed()
        );
    }
}
