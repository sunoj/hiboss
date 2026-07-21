// Purpose: Parse CLI commands, load configuration, and dispatch to command handlers.
// Exports: hiboss binary entry point.
// Dependencies: clap, tokio, crate::commands, crate::client, crate::config.

use clap::{Parser, Subcommand};
use hiboss::client;
use hiboss::commands::{
    agent, ask, boss, bot, channel, config as config_cmd, daemon, doctor, edit, forward, group,
    hook, inbox, init, react, read, reply, route, send, setup, ss, status, watch,
};
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
    #[command(about = "Edit the body of a previously sent message")]
    Edit(edit::Edit),
    #[command(about = "Forward a message to another channel")]
    Forward(forward::Forward),
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
    #[command(about = "Validate local configuration and connectivity")]
    Doctor(doctor::DoctorArgs),
    #[command(about = "Configure messaging channels (Discord, Telegram)")]
    Channel(channel::ChannelArgs),
    #[command(about = "Manage routing rules for incoming messages")]
    Route(route::RouteArgs),
    #[command(about = "Manage agent groups for broadcast messaging")]
    Group(group::GroupArgs),
    #[command(about = "Manage boss identities and permissions")]
    Boss(boss::BossArgs),
    #[command(about = "Session status board")]
    Ss(ss::SsArgs),
    #[command(about = "Background SSE daemon for real-time message delivery")]
    Daemon(daemon::DaemonArgs),
}

#[tokio::main]
async fn main() {
    if let Err(err) = run().await {
        let msg = err.to_string();
        eprintln!("Error: {}", msg);
        let code = if msg.contains("not configured")
            || msg.contains("missing")
            || msg.contains("config")
        {
            3
        } else if msg.contains("request failed")
            || msg.contains("connect")
            || msg.contains("timeout")
        {
            2
        } else {
            1
        };
        std::process::exit(code);
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
        Commands::Setup(args) if !setup::needs_client(args) => {
            setup::run(args)?;
            return Ok(());
        }
        Commands::Doctor(args) => {
            doctor::run(args, &config).await?;
            return Ok(());
        }
        Commands::Daemon(args) => {
            daemon::run(args).await?;
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
        Commands::Edit(args) => edit::run(args, &config, &client).await?,
        Commands::Forward(args) => forward::run(args, &config, &client).await?,
        Commands::Status(args) => status::run(args, &config, &client).await?,
        Commands::Agent(args) => agent::run(&args.command, &config, &client).await?,
        Commands::Channel(args) => channel::run(args, &config, &client).await?,
        Commands::Bot(args) => bot::run(args, &config, &client).await?,
        Commands::Watch(args) => watch::run(args, &config, &client).await?,
        Commands::Route(args) => route::run(args, &config, &client).await?,
        Commands::Group(args) => group::run(args, &config, &client).await?,
        Commands::Boss(args) => boss::run(args, &config, &client).await?,
        Commands::Ss(args) => ss::run(args, &config, &client).await?,
        Commands::Setup(args) => setup::run_with_client(args, &config, &client).await?,
        Commands::Hook(_) => unreachable!(),
        Commands::Config(_) => unreachable!(),
        Commands::Init(_) => unreachable!(),
        Commands::Doctor(_) => unreachable!(),
        Commands::Daemon(_) => unreachable!(),
    }
    Ok(())
}
