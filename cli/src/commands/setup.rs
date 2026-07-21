// Purpose: Guided setup wizards for hooks, Telegram, and Discord channels.
// Exports: SetupArgs, SetupCommand, run (hooks), run_with_client (channels).
// Dependencies: clap, serde_json, reqwest, crate::client, crate::config, setup_hooks.

#[path = "setup_support.rs"]
mod setup_support;

use crate::client::HiBossClient;
use crate::commands::setup_hooks::{self, SetupHooksArgs};
use crate::config::Config;
use clap::{Args, Subcommand};
use serde_json::{Value, json};
use std::error::Error;
use std::io::{self, Write};

use self::setup_support::{
    discord_api, extract_chats, extract_telegram_bot_token, list_text_channels,
    register_telegram_commands, select_chat, telegram_set_webhook_payload,
    telegram_webhook_secret_reminder, tg_api,
};

#[derive(Debug, Args)]
pub struct SetupArgs {
    #[command(subcommand)]
    pub command: SetupCommand,
}

#[derive(Debug, Subcommand)]
pub enum SetupCommand {
    #[command(about = "Configure Claude Code hooks for hiboss")]
    Hooks(SetupHooksArgs),
    #[command(about = "Guided Telegram bot setup")]
    Telegram(SetupTelegramArgs),
    #[command(
        name = "telegram-commands",
        about = "Register Telegram bot commands from saved channel config"
    )]
    TelegramCommands,
    #[command(about = "Guided Discord bot setup")]
    Discord(SetupDiscordArgs),
}

#[derive(Debug, Args)]
pub struct SetupTelegramArgs {
    #[arg(long, help = "Bot token from @BotFather (skip interactive prompt)")]
    pub bot_token: Option<String>,
    #[arg(long, help = "Chat ID (skip auto-detection)")]
    pub chat_id: Option<String>,
    #[arg(
        long,
        help = "Secret token sent by Telegram and verified by the server webhook"
    )]
    pub webhook_secret: Option<String>,
    #[arg(long, help = "Enable per-agent topic threads in a Telegram group")]
    pub use_topics: bool,
}

#[derive(Debug, Args)]
pub struct SetupDiscordArgs {
    #[arg(long, help = "Discord Bot Token (skip interactive prompt)")]
    pub bot_token: Option<String>,
    #[arg(long, help = "Channel ID (skip interactive selection)")]
    pub channel_id: Option<String>,
    #[arg(long, help = "Webhook URL for rich message formatting")]
    pub webhook_url: Option<String>,
}

pub fn run(args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    match &args.command {
        SetupCommand::Hooks(a) => setup_hooks::run_setup_hooks(a),
        _ => Err("This setup command requires server access.".into()),
    }
}

pub fn needs_client(args: &SetupArgs) -> bool {
    !matches!(&args.command, SetupCommand::Hooks(_))
}

pub async fn run_with_client(
    args: &SetupArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        SetupCommand::Telegram(tg) => run_telegram_setup(tg, config, client).await,
        SetupCommand::TelegramCommands => run_telegram_commands_setup(client).await,
        SetupCommand::Discord(dc) => run_discord_setup(dc, config, client).await,
        SetupCommand::Hooks(_) => unreachable!(),
    }
}

fn prompt(msg: &str) -> Result<String, Box<dyn Error>> {
    eprint!("{}", msg);
    io::stderr().flush()?;
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;
    Ok(buf.trim().to_owned())
}

async fn run_telegram_setup(
    args: &SetupTelegramArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let http = reqwest::Client::new();
    let server_url = config.require_server()?;

    // Step 1: Get bot token
    let bot_token = if let Some(ref t) = args.bot_token {
        t.clone()
    } else {
        eprintln!("=== Telegram Bot Setup ===\n");
        eprintln!("Step 1: Create a Telegram bot");
        eprintln!("  1. Open Telegram and message @BotFather");
        eprintln!("  2. Send /newbot and follow the prompts");
        eprintln!("  3. Copy the bot token (looks like 123456:ABC-DEF...)\n");
        let token = prompt("Paste your bot token: ")?;
        if token.is_empty() {
            return Err("Bot token is required".into());
        }
        token
    };

    // Validate token
    eprint!("Validating bot token... ");
    let me: Value = tg_api(&http, &bot_token, "getMe", &json!({})).await?;
    let bot_name = me["result"]["username"].as_str().unwrap_or("unknown");
    eprintln!("OK (@{})", bot_name);

    // Step 2: Get chat ID
    let chat_id = if let Some(ref id) = args.chat_id {
        id.clone()
    } else {
        eprintln!("\nStep 2: Connect bot to a chat");
        eprintln!(
            "  1. Add @{} to a group, OR send it a direct message",
            bot_name
        );
        eprintln!("  2. Send any message to the bot/group now\n");
        prompt("Press Enter when you've sent a message... ")?;

        eprint!("Detecting chat ID... ");
        let updates: Value = tg_api(
            &http,
            &bot_token,
            "getUpdates",
            &json!({"limit": 10, "offset": -10}),
        )
        .await?;
        let chats = extract_chats(&updates);
        if chats.is_empty() {
            eprintln!("FAILED");
            eprintln!("\nNo messages found. Ensure you sent a message after creating the bot.");
            eprintln!("Manual fallback: hiboss setup telegram --bot-token <token> --chat-id <id>");
            return Err("No chats detected".into());
        }
        select_chat(&chats)?
    };

    // Step 3: Save config + webhook
    eprintln!("\nStep 3: Saving configuration...");
    let mut cfg = json!({ "chat_id": chat_id, "bot_token": bot_token });
    if args.use_topics {
        cfg["use_topics"] = json!(true);
    }
    client.set_channel("telegram", &cfg).await?;
    eprintln!("  Channel config saved.");

    let base = server_url.trim_end_matches('/');
    let webhook_url = format!("{}/api/webhooks/telegram", base);
    eprint!("  Setting webhook... ");
    let wh: Value = tg_api(
        &http,
        &bot_token,
        "setWebhook",
        &telegram_set_webhook_payload(&webhook_url, args.webhook_secret.as_deref()),
    )
    .await?;
    if wh["ok"].as_bool() == Some(true) {
        eprintln!("OK");
    } else {
        eprintln!("WARNING: {}", wh["description"].as_str().unwrap_or("?"));
    }

    // Step 4: Test message
    eprint!("  Sending test message... ");
    let test = tg_api(
        &http,
        &bot_token,
        "sendMessage",
        &json!({
            "chat_id": chat_id,
            "text": "hiboss connected! This bot will relay messages between you and your AI agents."
        }),
    )
    .await;
    if test.is_ok() {
        eprintln!("OK");
    } else {
        eprintln!("FAILED (check permissions)");
    }

    eprintln!("\n=== Telegram setup complete! ===");
    eprintln!("Bot @{} connected to chat {}.", bot_name, chat_id);
    if let Some(reminder) = telegram_webhook_secret_reminder(args.webhook_secret.as_deref()) {
        eprintln!("{}", reminder);
    }
    eprintln!("Try: hiboss send \"Hello from my agent!\"");
    Ok(())
}

async fn run_telegram_commands_setup(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let channels = client.list_channels().await?;
    let bot_token = extract_telegram_bot_token(&channels.channels)
        .ok_or("enabled telegram channel with bot_token not found")?;
    eprint!("Registering Telegram bot commands... ");
    let response = register_telegram_commands(&reqwest::Client::new(), &bot_token).await?;
    if response["ok"].as_bool() != Some(true) {
        let description = response["description"].as_str().unwrap_or("unknown error");
        return Err(format!("Telegram command registration failed: {}", description).into());
    }
    eprintln!("OK");
    eprintln!("Registered /msg and /status.");
    Ok(())
}

async fn run_discord_setup(
    args: &SetupDiscordArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let http = reqwest::Client::new();
    let server_url = config.require_server()?;

    // Step 1: Get bot token
    let bot_token = if let Some(ref t) = args.bot_token {
        t.clone()
    } else {
        eprintln!("=== Discord Bot Setup ===\n");
        eprintln!("Step 1: Create a Discord application & bot");
        eprintln!("  1. Go to https://discord.com/developers/applications");
        eprintln!("  2. Click 'New Application' > create it");
        eprintln!("  3. Bot tab > 'Reset Token' > copy the token");
        eprintln!("  4. Enable MESSAGE CONTENT INTENT in Bot tab\n");
        let token = prompt("Paste your bot token: ")?;
        if token.is_empty() {
            return Err("Bot token is required".into());
        }
        token
    };

    // Validate and get app info
    eprint!("Validating bot token... ");
    let app = discord_api(&http, &bot_token, "GET", "oauth2/applications/@me", None).await?;
    let app_id = app["id"].as_str().unwrap_or("?").to_owned();
    let app_name = app["name"].as_str().unwrap_or("?");
    eprintln!("OK ({}, ID: {})", app_name, app_id);

    // Step 2: Select channel
    let channel_id = if let Some(ref id) = args.channel_id {
        id.clone()
    } else {
        eprintln!("\nStep 2: Select a Discord channel");
        eprintln!("  Invite the bot first:");
        eprintln!(
            "  https://discord.com/oauth2/authorize?client_id={}&scope=bot&permissions=2048\n",
            app_id
        );

        eprint!("Fetching channels... ");
        let guilds: Vec<Value> = serde_json::from_value(
            discord_api(&http, &bot_token, "GET", "users/@me/guilds", None).await?,
        )?;
        eprintln!("found {} server(s)", guilds.len());

        let channels = list_text_channels(&http, &bot_token, &guilds).await;
        if channels.is_empty() {
            return Err("No text channels found. Invite the bot first.".into());
        }

        eprintln!("\nAvailable channels:");
        for (i, (id, name, guild)) in channels.iter().enumerate() {
            eprintln!("  [{}] {} / #{} ({})", i + 1, guild, name, id);
        }
        let choice = prompt("\nSelect channel number [1]: ")?;
        let idx: usize = choice.parse().unwrap_or(1);
        if idx < 1 || idx > channels.len() {
            return Err("Invalid selection".into());
        }
        channels[idx - 1].0.clone()
    };

    // Step 3: Register slash commands
    let base = server_url.trim_end_matches('/');
    eprint!("\nStep 3: Registering /msg slash command... ");
    let reg_resp = http
        .post(format!(
            "{}/api/webhooks/discord-interactions/register-commands",
            base
        ))
        .json(&json!({ "app_id": app_id, "bot_token": bot_token }))
        .send()
        .await?;
    if reg_resp.status().is_success() {
        eprintln!("OK");
    } else {
        eprintln!("FAILED ({})", reg_resp.text().await.unwrap_or_default());
    }

    // Step 4: Save config
    eprint!("  Saving channel config... ");
    let mut cfg = json!({ "bot_token": bot_token, "channel_id": channel_id });
    if let Some(ref wh_url) = args.webhook_url {
        cfg["webhook_url"] = json!(wh_url);
    }
    client.set_channel("discord", &cfg).await?;
    eprintln!("OK");

    eprintln!("\n=== Discord setup almost complete! ===\n");
    eprintln!("One manual step for boss → agent messaging:\n");
    eprintln!(
        "  1. Discord Developer Portal > {} > General Information",
        app_name
    );
    eprintln!("  2. Set Interactions Endpoint URL to:");
    eprintln!("     {}/api/webhooks/discord-interactions", base);
    eprintln!("  3. Copy PUBLIC KEY from same page, then run:");
    eprintln!("     wrangler secret put DISCORD_PUBLIC_KEY\n");
    eprintln!("Try: hiboss send \"Hello from Discord!\"");
    Ok(())
}
