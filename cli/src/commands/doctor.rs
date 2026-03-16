// Purpose: Validate hiboss CLI configuration and connectivity before use.
// Exports: DoctorArgs and run().
// Dependencies: clap, colored, crate::client, crate::config, std::error::Error, std::process.

use clap::Args;
use colored::Colorize;
use crate::client::HiBossClient;
use crate::config::{config_path, Config};
use std::{error::Error, process};

#[derive(Debug, Args)]
pub struct DoctorArgs;

pub async fn run(config: &Config) -> Result<(), Box<dyn Error>> {
    let mut issues = 0;
    let path = config_path();
    let exists = path.is_file();
    println!("Config file: {} {}", path.display(), if exists { "OK".green() } else { "MISSING".red() });
    if !exists {
        issues += 1;
    }

    let server = config.server.as_deref().filter(|value| !value.trim().is_empty());
    if let Some(url) = server {
        println!("Server: {} {}", url, "OK".green());
    } else {
        println!("Server: {} {}", "not set", "MISSING".red());
        issues += 1;
    }

    let key = config.key.as_deref().filter(|value| !value.trim().is_empty());
    if let Some(value) = key {
        println!("Key: {} {}", mask_key(value), "OK".green());
    } else {
        println!("Key: {} {}", "not set", "MISSING".red());
        issues += 1;
    }

    let channel = config.channel.as_deref().filter(|value| !value.trim().is_empty());
    if let Some(name) = channel {
        println!("Channel: {} {}", name, "OK".green());
    } else {
        println!("Channel: {} {}", "NOT SET", "WARN".yellow());
    }

    if let (Some(url), Some(value)) = (server, key) {
        let client = HiBossClient::new(url, value);
        match client.get_agent_config().await {
            Ok(agent) => {
                let name = agent["name"].as_str().unwrap_or("-");
                println!("Agent: {} {}", name, "OK".green());
                match client.list_channels().await {
                    Ok(channels) => {
                        if channels.channels.is_empty() {
                            println!("Channels: NONE");
                        } else {
                            let list = channels
                                .channels
                                .iter()
                                .map(|info| info.channel.clone())
                                .collect::<Vec<_>>()
                                .join(", ");
                            println!("Channels: {}", list);
                        }
                    }
                    Err(err) => {
                        println!("Channels: {} ({})", "FAIL".red(), err);
                        issues += 1;
                    }
                }
            }
            Err(err) => {
                println!("Agent: {} ({})", "FAIL".red(), err);
                issues += 1;
            }
        }
    } else {
        println!("Agent: skipped (missing server or key)");
    }

    if issues == 0 {
        println!("All checks passed");
    } else {
        println!("{} issues found", issues);
        process::exit(1);
    }

    Ok(())
}

fn mask_key(value: &str) -> String {
    if value.len() <= 8 {
        value.to_string()
    } else {
        let start = &value[..4];
        let end = &value[value.len() - 4..];
        format!("{}...{}", start, end)
    }
}
