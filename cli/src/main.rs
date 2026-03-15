// Purpose: Parse CLI commands, load configuration, and dispatch to command handlers.
// Exports: hiboss binary entry point.
// Dependencies: clap, tokio, crate::commands, crate::client, crate::config.

mod client;
mod commands;
mod config;
mod types;

use clap::{Parser, Subcommand};
use commands::{ask, config as config_cmd, inbox, read, reply, send, status};
use std::error::Error;

#[derive(Parser)]
#[command(author, version, about = "Agent ↔ Boss communication via HTTP", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Send(send::SendArgs),
    Ask(ask::AskArgs),
    Inbox(inbox::InboxArgs),
    Read(read::ReadArgs),
    Reply(reply::ReplyArgs),
    Status(status::StatusArgs),
    Config(config_cmd::ConfigArgs),
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
    if let Commands::Config(command) = &cli.command {
        config_cmd::run(&command.command, &mut config).await?;
        return Ok(());
    }
    let server = config.require_server()?;
    let key = config.require_key()?;
    let client = client::HiBossClient::new(&server, &key);
    match &cli.command {
        Commands::Send(args) => send::run(args, &config, &client).await?,
        Commands::Ask(args) => ask::run(args, &config, &client).await?,
        Commands::Inbox(args) => inbox::run(args, &config, &client).await?,
        Commands::Read(args) => read::run(args, &config, &client).await?,
        Commands::Reply(args) => reply::run(args, &config, &client).await?,
        Commands::Status(args) => status::run(args, &config, &client).await?,
        Commands::Config(_) => unreachable!(),
    }
    Ok(())
}
