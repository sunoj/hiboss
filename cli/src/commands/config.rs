// Purpose: Manage hiboss CLI configuration entries (server, key, channel).
// Exports: ConfigCommand, SetArgs, GetArgs, ConfigKey, and run().
// Dependencies: clap, crate::config, std::error::Error.

use crate::config::{Config, save_config};
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
            ConfigKey::Server => config
                .selected_profile
                .as_ref()
                .and_then(|name| config.profiles.get(name))
                .and_then(|profile| profile.server.clone())
                .filter(|server| !server.trim().is_empty())
                .or_else(|| config.server.clone()),
            ConfigKey::Key => config.key.as_deref().map(super::whoami::mask_key),
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
            println!(
                "server = {}",
                ConfigKey::Server.current(config).as_deref().unwrap_or("-")
            );
            println!(
                "key = {}",
                config
                    .key
                    .as_deref()
                    .map(super::whoami::mask_key)
                    .unwrap_or_else(|| "-".into())
            );
            println!("channel = {}", config.channel.as_deref().unwrap_or("-"));
        }
    }
    Ok(())
}
