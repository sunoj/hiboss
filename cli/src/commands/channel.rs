// Purpose: Manage channel configuration via the hiboss CLI.
// Exports: ChannelArgs, ChannelCommand, and run().
// Dependencies: clap, crate::client, crate::config, reqwest, serde_json.

use crate::{client::HiBossClient, config::Config};
use clap::{Args, Subcommand, ValueEnum};
use serde_json::json;
use std::error::Error;

#[derive(Debug, Args)]
pub struct ChannelArgs {
    #[command(subcommand)]
    pub command: ChannelCommand,
}

#[derive(Debug, Subcommand)]
pub enum ChannelCommand {
    Set(ChannelSetArgs),
    List,
    #[command(about = "Register Discord /msg slash command and print setup instructions")]
    DiscordSetup(DiscordSetupArgs),
}

#[derive(Debug, Args)]
pub struct DiscordSetupArgs {
    #[arg(long, help = "Discord Application ID")]
    pub app_id: String,
    #[arg(long, help = "Discord Bot Token")]
    pub bot_token: String,
}

#[derive(Clone, Debug, ValueEnum)]
pub enum ChannelKind {
    Discord,
    Telegram,
}

impl ChannelKind {
    fn as_str(&self) -> &'static str {
        match self {
            ChannelKind::Discord => "discord",
            ChannelKind::Telegram => "telegram",
        }
    }
}

#[derive(Debug, Args)]
pub struct ChannelSetArgs {
    #[arg(value_enum)]
    pub channel: ChannelKind,
    #[arg(long)]
    pub bot_token: Option<String>,
    #[arg(long)]
    pub channel_id: Option<String>,
    #[arg(long)]
    pub chat_id: Option<String>,
    #[arg(long)]
    pub webhook_url: Option<String>,
    #[arg(long)]
    pub avatar_url: Option<String>,
}

pub async fn run(args: &ChannelArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        ChannelCommand::Set(payload) => run_set(payload, config, client).await?,
        ChannelCommand::List => run_list(client).await?,
        ChannelCommand::DiscordSetup(payload) => run_discord_setup(payload, config).await?,
    }
    Ok(())
}

async fn run_set(args: &ChannelSetArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let config_payload = match args.channel {
        ChannelKind::Discord => {
            if let Some(ref url) = args.webhook_url {
                let mut cfg = json!({ "webhook_url": url });
                if let Some(ref avatar) = args.avatar_url {
                    cfg["avatar_url"] = json!(avatar);
                }
                cfg
            } else {
                let channel_id = args.channel_id.as_deref()
                    .ok_or_else(|| required_arg("discord needs --webhook-url or --bot-token + --channel-id"))?;
                let bot_token = args.bot_token.as_deref()
                    .ok_or_else(|| required_arg("discord needs --webhook-url or --bot-token + --channel-id"))?;
                json!({ "channel_id": channel_id, "bot_token": bot_token })
            }
        }
        ChannelKind::Telegram => {
            let chat_id = args.chat_id.as_deref()
                .ok_or_else(|| required_arg("chat-id is required for telegram"))?;
            let bot_token = args.bot_token.as_deref()
                .ok_or_else(|| required_arg("bot-token is required for telegram"))?;
            json!({ "chat_id": chat_id, "bot_token": bot_token })
        }
    };
    client.set_channel(args.channel.as_str(), &config_payload).await?;
    if let (ChannelKind::Telegram, Some(token)) = (&args.channel, &args.bot_token) {
        let server_url = config.require_server()?;
        let base = server_url.trim_end_matches('/');
        let webhook_url = format!("{}/api/webhooks/telegram", base);
        let tg_client = reqwest::Client::new();
        let tg_response = tg_client
            .post(format!("https://api.telegram.org/bot{}/setWebhook", token))
            .json(&json!({ "url": webhook_url }))
            .send()
            .await?;
        let body = tg_response.text().await?;
        eprintln!("Telegram webhook response: {}", body);
    }
    eprintln!("Channel configured");
    Ok(())
}

async fn run_list(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.list_channels().await?;
    println!("{:<10} {:<8} {}", "Channel", "Enabled", "Created");
    for channel in response.channels {
        let enabled = if channel.enabled { "true" } else { "false" };
        println!("{:<10} {:<8} {}", channel.channel, enabled, channel.created_at);
    }
    Ok(())
}

async fn run_discord_setup(args: &DiscordSetupArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let server_url = config.require_server()?;
    let base = server_url.trim_end_matches('/');
    let url = format!("{}/api/webhooks/discord-interactions/register-commands", base);
    let http = reqwest::Client::new();
    let response = http
        .post(&url)
        .json(&json!({ "app_id": args.app_id, "bot_token": args.bot_token }))
        .send()
        .await?;
    if !response.status().is_success() {
        let body = response.text().await?;
        return Err(format!("Discord command registration failed: {}", body).into());
    }
    eprintln!("Discord /msg slash command registered.");
    eprintln!("\nNext steps:");
    eprintln!("1. Go to Discord Developer Portal > Your App > General Information");
    eprintln!("2. Set Interactions Endpoint URL to: {}/api/webhooks/discord-interactions", base);
    eprintln!("3. Run: wrangler secret put DISCORD_PUBLIC_KEY");
    eprintln!("   Paste your app's PUBLIC KEY from the Developer Portal");
    Ok(())
}

fn required_arg(message: &str) -> Box<dyn Error> {
    message.to_string().into()
}
