// Purpose: Parse CLI commands, load configuration, and dispatch to command handlers.
// Exports: hiboss binary entry point.
// Dependencies: clap, tokio, crate::commands, crate::client, crate::config.

use clap::{Parser, Subcommand};
use hiboss::client;
use hiboss::commands::{agent, ask, bot, channel, config as config_cmd, hook, init, inbox, react, read, reply, send, setup, status, watch};
use hiboss::config;
use std::error::Error;

#[derive(Parser)]
#[command(author, version, about = "Agent ↔ Boss communication via HTTP", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Send an async message to your boss")]
    Send(send::SendArgs),
    #[command(about = "Send a blocking message and wait for boss reply")]
    Ask(ask::AskArgs),
    #[command(about = "List messages from your boss")]
    Inbox(inbox::InboxArgs),
    #[command(about = "Read a specific message with its reply chain")]
    Read(read::ReadArgs),
    #[command(about = "Set a reaction emoji on a message")]
    React(react::ReactArgs),
    #[command(about = "Reply to a message from your boss")]
    Reply(reply::ReplyArgs),
    #[command(about = "Check the status of a sent message")]
    Status(status::StatusArgs),
    #[command(about = "Manage agent identities")]
    Agent(agent::AgentArgs),
    #[command(about = "Auto-reply to messages using an external handler")]
    Bot(bot::BotArgs),
    #[command(about = "Watch for new messages with desktop notifications")]
    Watch(watch::WatchArgs),
    #[command(about = "Initialize hiboss with a server URL")]
    Init(init::InitArgs),
    #[command(about = "Manage local configuration")]
    Config(config_cmd::ConfigArgs),
    #[command(about = "Run Claude Code hook events")]
    Hook(hook::HookArgs),
    #[command(about = "Setup integrations (hooks, etc.)")]
    Setup(setup::SetupArgs),
    #[command(about = "Configure messaging channels (Discord, Telegram)")]
    Channel(channel::ChannelArgs),
}

#[tokio::main]
async fn main() {
    if let Err(err) = run().await {
        eprintln!("Error: {}", err);
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn Error>> {
    let cli = Cli::parse();
    let mut config = config::load_config()?;
    match &cli.command {
        Commands::Config(command) => {
            config_cmd::run(&command.command, &mut config).await?;
            return Ok(());
        }
        Commands::Init(command) => {
            init::run(command, &mut config).await?;
            return Ok(());
        }
        Commands::Hook(args) => {
            hook::run(args).await?;
            return Ok(());
        }
        Commands::Setup(args) => {
            setup::run(args)?;
            return Ok(());
        }
        _ => {}
    }
    let server = config.require_server()?;
    let key = config.require_key()?;
    let client = client::HiBossClient::new(&server, &key);
    match &cli.command {
        Commands::Send(args) => send::run(args, &config, &client).await?,
        Commands::Ask(args) => ask::run(args, &config, &client).await?,
        Commands::Inbox(args) => inbox::run(args, &config, &client).await?,
        Commands::Read(args) => read::run(args, &config, &client).await?,
        Commands::React(args) => react::run(args, &config, &client).await?,
        Commands::Reply(args) => reply::run(args, &config, &client).await?,
        Commands::Status(args) => status::run(args, &config, &client).await?,
        Commands::Agent(args) => agent::run(&args.command, &config, &client).await?,
        Commands::Channel(args) => channel::run(args, &config, &client).await?,
        Commands::Bot(args) => bot::run(args, &config, &client).await?,
        Commands::Watch(args) => watch::run(args, &config, &client).await?,
        Commands::Hook(_) => unreachable!(),
        Commands::Setup(_) => unreachable!(),
        Commands::Config(_) => unreachable!(),
        Commands::Init(_) => unreachable!(),
    }
    Ok(())
}
