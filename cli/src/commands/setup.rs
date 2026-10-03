// Purpose: Guided setup wizards for hooks, Telegram, and Discord channels.
// Exports: SetupArgs, SetupCommand, run (hooks), run_with_client (channels).
// Dependencies: clap, serde_json, reqwest, crate::client, crate::config, setup_hooks.

#[path = "setup_support.rs"]
mod setup_support;

use crate::client::HiBossClient;
use crate::commands::setup_hooks;
use crate::config::Config;
use std::error::Error;
use std::io::{self, Write};

use self::setup_support::{extract_telegram_bot_token, register_telegram_commands};
#[path = "setup_discord.rs"]
mod discord;
#[path = "setup_telegram.rs"]
mod telegram;
use discord::run_discord_setup;
use telegram::run_telegram_setup;

#[path = "setup_args.rs"]
mod arguments;
pub use arguments::{SetupArgs, SetupCommand, SetupDiscordArgs, SetupTelegramArgs};

pub fn run(args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    match &args.command {
        Some(SetupCommand::Hooks(a)) => setup_hooks::run_setup_hooks(a),
        Some(SetupCommand::Agents(a)) => crate::commands::setup_agents::run(a),
        _ => Err("This setup command requires server access.".into()),
    }
}

pub fn needs_client(args: &SetupArgs) -> bool {
    matches!(
        &args.command,
        Some(SetupCommand::Telegram(_) | SetupCommand::TelegramCommands | SetupCommand::Discord(_))
    )
}

pub async fn run_with_client(
    args: &SetupArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        Some(SetupCommand::Telegram(tg)) => run_telegram_setup(tg, config, client).await,
        Some(SetupCommand::TelegramCommands) => run_telegram_commands_setup(client).await,
        Some(SetupCommand::Discord(dc)) => run_discord_setup(dc, config, client).await,
        _ => Err("This setup command does not require server access.".into()),
    }
}

fn prompt(msg: &str) -> Result<String, Box<dyn Error>> {
    eprint!("{}", msg);
    io::stderr().flush()?;
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;
    Ok(buf.trim().to_owned())
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
