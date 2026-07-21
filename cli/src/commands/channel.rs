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
    #[arg(
        long,
        help = "Discord Application ID (auto-detected from bot token if omitted)"
    )]
    pub app_id: Option<String>,
    #[arg(long, help = "Discord Bot Token")]
    pub bot_token: String,
    #[arg(long, help = "Discord Channel ID for the bot to operate in")]
    pub channel_id: Option<String>,
    #[arg(long, help = "Discord Webhook URL (for rich message formatting)")]
    pub webhook_url: Option<String>,
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
    #[arg(
        long,
        help = "Auto-create Telegram topic per agent (requires topics-enabled group)"
    )]
    pub use_topics: bool,
    #[arg(
        long,
        help = "Telegram forum topic thread ID (set manually or auto-created)"
    )]
    pub topic_id: Option<i64>,
}

pub async fn run(
    args: &ChannelArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        ChannelCommand::Set(payload) => run_set(payload, config, client).await?,
        ChannelCommand::List => run_list(client).await?,
        ChannelCommand::DiscordSetup(payload) => run_discord_setup(payload, config, client).await?,
    }
    Ok(())
}

async fn run_set(
    args: &ChannelSetArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let config_payload = match args.channel {
        ChannelKind::Discord => {
            if let Some(ref url) = args.webhook_url {
                let mut cfg = json!({ "webhook_url": url });
                if let Some(ref avatar) = args.avatar_url {
                    cfg["avatar_url"] = json!(avatar);
                }
                // Include bot_token + channel_id for reaction support in webhook mode
                if let Some(ref token) = args.bot_token {
                    cfg["bot_token"] = json!(token);
                }
                if let Some(ref ch_id) = args.channel_id {
                    cfg["channel_id"] = json!(ch_id);
                }
                cfg
            } else {
                let channel_id = args.channel_id.as_deref().ok_or_else(|| {
                    required_arg("discord needs --webhook-url or --bot-token + --channel-id")
                })?;
                let bot_token = args.bot_token.as_deref().ok_or_else(|| {
                    required_arg("discord needs --webhook-url or --bot-token + --channel-id")
                })?;
                json!({ "channel_id": channel_id, "bot_token": bot_token })
            }
        }
        ChannelKind::Telegram => {
            let chat_id = args
                .chat_id
                .as_deref()
                .ok_or_else(|| required_arg("chat-id is required for telegram"))?;
            let bot_token = args
                .bot_token
                .as_deref()
                .ok_or_else(|| required_arg("bot-token is required for telegram"))?;
            let mut cfg = json!({ "chat_id": chat_id, "bot_token": bot_token });
            if args.use_topics {
                cfg["use_topics"] = json!(true);
            }
            if let Some(tid) = args.topic_id {
                cfg["message_thread_id"] = json!(tid);
            }
            cfg
        }
    };
    client
        .set_channel(args.channel.as_str(), &config_payload)
        .await?;
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
        println!(
            "{:<10} {:<8} {}",
            channel.channel, enabled, channel.created_at
        );
    }
    Ok(())
}

async fn run_discord_setup(
    args: &DiscordSetupArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let http = reqwest::Client::new();
    // 1. Auto-detect app_id from bot token if not provided
    let app_id = if let Some(ref id) = args.app_id {
        id.clone()
    } else {
        eprintln!("Auto-detecting Application ID from bot token...");
        let resp = http
            .get("https://discord.com/api/v10/oauth2/applications/@me")
            .header("Authorization", format!("Bot {}", args.bot_token))
            .send()
            .await?;
        if !resp.status().is_success() {
            return Err("Failed to auto-detect app_id. Provide --app-id manually.".into());
        }
        let app: serde_json::Value = resp.json().await?;
        let id = app["id"]
            .as_str()
            .ok_or("Could not read app id from Discord API")?;
        eprintln!("Detected Application ID: {}", id);
        id.to_owned()
    };
    // 2. If no channel_id, list guild channels to help the user pick
    let channel_id = if let Some(ref ch_id) = args.channel_id {
        ch_id.clone()
    } else {
        eprintln!("No --channel-id provided. Listing available channels...");
        let guilds_resp = http
            .get("https://discord.com/api/v10/users/@me/guilds")
            .header("Authorization", format!("Bot {}", args.bot_token))
            .send()
            .await?;
        if !guilds_resp.status().is_success() {
            return Err("Failed to list guilds. Provide --channel-id manually.".into());
        }
        let guilds: Vec<serde_json::Value> = guilds_resp.json().await?;
        let mut found_channel = None;
        for guild in &guilds {
            let guild_id = guild["id"].as_str().unwrap_or_default();
            let guild_name = guild["name"].as_str().unwrap_or("?");
            let ch_resp = http
                .get(format!(
                    "https://discord.com/api/v10/guilds/{}/channels",
                    guild_id
                ))
                .header("Authorization", format!("Bot {}", args.bot_token))
                .send()
                .await?;
            if !ch_resp.status().is_success() {
                continue;
            }
            let channels: Vec<serde_json::Value> = ch_resp.json().await?;
            let text_channels: Vec<_> = channels
                .iter()
                .filter(|c| c["type"].as_u64() == Some(0))
                .collect();
            if !text_channels.is_empty() {
                eprintln!("\nGuild: {}", guild_name);
                for ch in &text_channels {
                    eprintln!(
                        "  #{:<30} {}",
                        ch["name"].as_str().unwrap_or("?"),
                        ch["id"].as_str().unwrap_or("?")
                    );
                }
                if found_channel.is_none() {
                    found_channel = text_channels
                        .first()
                        .and_then(|c| c["id"].as_str().map(String::from));
                }
            }
        }
        return Err("Please re-run with --channel-id <id> from the list above.".into());
    };
    // 3. Register slash commands
    let server_url = config.require_server()?;
    let base = server_url.trim_end_matches('/');
    let url = format!(
        "{}/api/webhooks/discord-interactions/register-commands",
        base
    );
    let response = http
        .post(&url)
        .json(&json!({ "app_id": app_id, "bot_token": args.bot_token }))
        .send()
        .await?;
    if !response.status().is_success() {
        let body = response.text().await?;
        return Err(format!("Discord command registration failed: {}", body).into());
    }
    eprintln!("Discord /msg slash command registered.");
    // 4. Save channel config with all fields
    let mut cfg = json!({ "bot_token": args.bot_token, "channel_id": channel_id });
    if let Some(ref wh_url) = args.webhook_url {
        cfg["webhook_url"] = json!(wh_url);
    }
    client.set_channel("discord", &cfg).await?;
    eprintln!(
        "Discord channel config saved (bot_token + channel_id{}).",
        if args.webhook_url.is_some() {
            " + webhook_url"
        } else {
            ""
        },
    );
    eprintln!("\nNext steps:");
    eprintln!("1. Go to Discord Developer Portal > Your App > General Information");
    eprintln!(
        "2. Set Interactions Endpoint URL to: {}/api/webhooks/discord-interactions",
        base
    );
    eprintln!("3. Run: wrangler secret put DISCORD_PUBLIC_KEY");
    eprintln!("   Paste your app's PUBLIC KEY from the Developer Portal");
    Ok(())
}

fn required_arg(message: &str) -> Box<dyn Error> {
    message.to_string().into()
}
