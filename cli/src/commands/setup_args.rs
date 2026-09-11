// Defines setup CLI arguments for channels, hooks, and global agent guidance.
// Exports setup argument structs and the subcommand enum.
// Dependencies: clap and SetupHooksArgs.
use clap::{Args, Subcommand};
use crate::commands::setup_hooks::SetupHooksArgs;

#[derive(Debug, Args)]
pub struct SetupArgs {
    #[command(subcommand)]
    pub command: SetupCommand,
}

#[derive(Debug, Subcommand)]
pub enum SetupCommand {
    #[command(about = "Install or refresh global Codex and Claude HiBoss delivery and questionnaire guidance")]
    Agents(crate::commands::setup_agents::SetupAgentsArgs),
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

