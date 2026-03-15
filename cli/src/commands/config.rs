// Purpose: Manage hiboss CLI configuration entries (server, key, channel).
// Exports: ConfigCommand, SetArgs, GetArgs, ConfigKey, and run().
// Dependencies: clap, crate::config, std::error::Error.

use crate::config::{save_config, Config};
use clap::{Args, Subcommand, ValueEnum};
use std::error::Error;

#[derive(Debug, Args)]
pub struct ConfigArgs {
    #[command(subcommand)]
    pub command: ConfigCommand,
}

#[derive(Debug, Subcommand)]
pub enum ConfigCommand {
    Set(SetArgs),
    Get(GetArgs),
    List,
}

#[derive(Debug, Args)]
pub struct SetArgs {
    #[arg(value_enum)]
    pub key: ConfigKey,
    #[arg(value_name = "value")]
    pub value: String,
}

#[derive(Debug, Args)]
pub struct GetArgs {
    #[arg(value_enum)]
    pub key: ConfigKey,
}

#[derive(Clone, Debug, ValueEnum)]
pub enum ConfigKey {
    Server,
    Key,
    Channel,
}

impl ConfigKey {
    fn apply(&self, config: &mut Config, value: String) {
        match self {
            ConfigKey::Server => config.server = Some(value),
            ConfigKey::Key => config.key = Some(value),
            ConfigKey::Channel => config.channel = Some(value),
        }
    }

    fn current(&self, config: &Config) -> Option<String> {
        match self {
            ConfigKey::Server => config.server.clone(),
            ConfigKey::Key => config.key.clone(),
            ConfigKey::Channel => config.channel.clone(),
        }
    }
}

pub async fn run(command: &ConfigCommand, config: &mut Config) -> Result<(), Box<dyn Error>> {
    match command {
        ConfigCommand::Set(args) => {
            args.key.apply(config, args.value.clone());
            save_config(config)?;
            eprintln!("Config updated");
        }
        ConfigCommand::Get(args) => {
            let value = args.key.current(config).unwrap_or_else(|| "-".to_string());
            println!("{}", value);
        }
        ConfigCommand::List => {
            println!("server = {}", config.server.as_deref().unwrap_or("-"));
            println!("key = {}", config.key.as_deref().unwrap_or("-"));
            println!("channel = {}", config.channel.as_deref().unwrap_or("-"));
        }
    }
    Ok(())
}
