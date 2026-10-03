// Purpose: Parse CLI commands, load configuration, and dispatch to command handlers.
// Exports: hiboss binary entry point.
// Dependencies: clap, tokio, crate::commands, crate::client, crate::config.

use clap::{CommandFactory, FromArgMatches, Parser, Subcommand};
use hiboss::client;
use hiboss::commands::{
    agent, ask, boss, bot, channel, config as config_cmd, daemon, doctor, edit, forward, group,
    device, hook, inbox, key, onboarding, panel, progress, react, read, reply, request, route, send, setup, ss,
    status, watch, whoami,
};
use hiboss::config;
use hiboss::help;
use hiboss::message_security::MessageVerificationError;
use std::error::Error;

#[derive(Parser)]
#[command(author, version, about = "Agent ↔ Boss communication via HTTP", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Send a message, progress note, result or report to your boss")]
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
    #[command(about = "List, rotate and revoke agent credentials")]
    Key(key::KeyArgs),
    #[command(about = "Auto-reply to messages using an external handler")]
    Bot(bot::BotArgs),
    #[command(about = "Watch for new messages with desktop notifications")]
    Watch(watch::WatchArgs),
    #[command(about = "Invite another machine using the active profile")]
    Device(device::DeviceArgs),
    #[command(about = "Manage local configuration")]
    Config(config_cmd::ConfigArgs),
    #[command(about = "Run Claude Code hook events")]
    Hook(hook::HookArgs),
    #[command(about = "Set up runtime profiles or configure integrations")]
    Setup(setup::SetupArgs),
    #[command(about = "Validate local configuration and connectivity")]
    Doctor(doctor::DoctorArgs),
    #[command(about = "Show the active local credential identity")]
    Whoami(whoami::WhoamiArgs),
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
    #[command(about = "Post and browse project progress updates")]
    Progress(progress::ProgressArgs),
    #[command(about = "Manage project profiles and aliases")]
    Project(progress::progress_team::TeamArgs),
    #[command(about = "Display live state the boss can watch change in panels")]
    Panel(panel::PanelArgs),
    #[command(about = "Publish and receive durable structured questionnaire answers")]
    Request(request::RequestArgs),
}

#[tokio::main]
async fn main() {
    if let Err(err) = run().await {
        let msg = err.to_string();
        if err.is::<config::ProfileError>() {
            eprintln!("{msg}");
        } else {
            eprintln!("Error: {msg}");
        }
        // Typed failures first: their messages can contain classifier words like "missing".
        let code = if err.is::<config::ProfileError>() {
            3
        } else if err.is::<config::LoadError>() || err.is::<MessageVerificationError>() {
            1
        } else if msg.contains("not configured")
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
    let matches = help::grouped_root_command(Cli::command()).get_matches();
    let cli = Cli::from_arg_matches(&matches).unwrap_or_else(|err| err.exit());
    if run_offline(&cli.command).await? {
        return Ok(());
    }
    let mut config = config::load_config()?;
    if run_local(&cli.command, &mut config).await? {
        return Ok(());
    }
    let credential = config::resolve_credentials(&config)?;
    let client = client::HiBossClient::new(&credential.server, &credential.key);
    run_remote(&cli.command, &config, &client).await
}

async fn run_remote(
    command: &Commands,
    config: &config::Config,
    client: &client::HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match command {
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
        Commands::Key(args) => key::run(args, &config).await?,
        Commands::Channel(args) => channel::run(args, &config, &client).await?,
        Commands::Bot(args) => bot::run(args, &config, &client).await?,
        Commands::Watch(args) => watch::run(args, &config, &client).await?,
        Commands::Route(args) => route::run(args, &config, &client).await?,
        Commands::Group(args) => group::run(args, &config, &client).await?,
        Commands::Boss(args) => boss::run(args, &config, &client).await?,
        Commands::Device(args) => device::run(args, config).await?,
        Commands::Ss(args) => ss::run(args, &config, &client).await?,
        Commands::Setup(args) => setup::run_with_client(args, &config, &client).await?,
        Commands::Progress(args) => progress::run(args, &config, &client).await?,
        Commands::Project(args) => progress::progress_team::run(args, &config, &client).await?,
        Commands::Panel(args) => panel::run(args, &client).await?,
        Commands::Request(args) => request::run(args, &client).await?,
        Commands::Hook(_) => unreachable!(),
        Commands::Config(_) => unreachable!(),
        Commands::Doctor(_) => unreachable!(),
        Commands::Daemon(_) => unreachable!(),
        Commands::Whoami(_) => unreachable!(),
    }
    Ok(())
}

/// Commands that do not require parseable configuration in the top-level dispatcher.
async fn run_offline(command: &Commands) -> Result<bool, Box<dyn Error>> {
    match command {
        Commands::Hook(args) => hook::run(args).await?,
        Commands::Setup(args) if args.command.is_none() => onboarding::run(args).await?,
        Commands::Setup(args) if !setup::needs_client(args) => setup::run(args)?,
        Commands::Panel(args) => match &args.command {
            panel::PanelCommand::Guide => {
                println!("{}", hiboss::commands::setup_agents::PANEL_GUIDE)
            }
            panel::PanelCommand::Validate(arguments) => panel::run_validate(arguments)?,
            panel::PanelCommand::Example { name } => {
                print!("{}", panel::examples::render(name.as_deref())?)
            }
            _ => return Ok(false),
        },
        _ => return Ok(false),
    }
    Ok(true)
}

/// Commands that need a readable config file but not a configured server.
async fn run_local(
    command: &Commands,
    config: &mut config::Config,
) -> Result<bool, Box<dyn Error>> {
    match command {
        Commands::Config(command) => config_cmd::run(&command.command, config).await?,
        Commands::Doctor(args) => doctor::run(args, config).await?,
        Commands::Whoami(args) => whoami::run(args, config)?,
        Commands::Daemon(args) => daemon::run(args).await?,
        _ => return Ok(false),
    }
    Ok(true)
}

#[cfg(test)]
mod help_tests;
#[cfg(test)]
mod project_command_tests;
#[cfg(test)]
mod onboarding_command_tests;
