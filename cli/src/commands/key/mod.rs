// Agent credential commands and safe local rotation orchestration.
// Exports KeyArgs and run; depends on reqwest, config and atomic config storage.
mod api;
mod storage;
#[cfg(test)]
mod tests;

use clap::{Args, Subcommand};
use crate::config::Config;
use std::{error::Error, path::Path};
use api::KeyApi;
use storage::RotationConfig;

#[derive(Args)]
pub struct KeyArgs {
    #[command(subcommand)]
    pub command: KeyCommand,
}

#[derive(Subcommand)]
pub enum KeyCommand {
    /// List credential metadata for this agent
    List,
    /// Verify and install a new credential, then revoke the previous one
    Rotate { #[arg(long)] label: Option<String> },
    /// Revoke one credential by its full ID
    Revoke { id: String },
}

pub async fn run(args: &KeyArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let api = KeyApi::new(&config.require_server()?, &config.require_key()?);
    match &args.command {
        KeyCommand::List => println!("{}", serde_json::to_string_pretty(&api.list().await?)?),
        KeyCommand::Revoke { id } => {
            api.revoke(id).await?;
            println!("Revoked key {id}");
        }
        KeyCommand::Rotate { label } => {
            let id = rotate(config, &crate::config::config_path(), label.as_deref().unwrap_or("rotated")).await?;
            println!("Installed key {id}; previous key revoked.");
        }
    }
    Ok(())
}

async fn rotate(config: &Config, path: &Path, label: &str) -> Result<String, Box<dyn Error>> {
    let mut storage = RotationConfig::open(path, &config.require_key()?)
        .map_err(|error| format!("rotation not started: {error}; previous active configuration unchanged"))?;
    let old = KeyApi::new(&config.require_server()?, &config.require_key()?);
    let result = rotate_saved(&old, config, label, &mut storage).await;
    match result {
        Ok(id) => {
            storage.finish().map_err(|error| format!("new key installed and previous key revoked; backup retained at {}: {error}", storage.backup_path().display()))?;
            Ok(id)
        }
        Err(error) => Err(format!("{error}; previous key retained at {}", storage.backup_path().display()).into()),
    }
}

async fn rotate_saved(old: &KeyApi, config: &Config, label: &str,
    storage: &mut RotationConfig) -> Result<String, Box<dyn Error>> {
    let identity = old.me().await?;
    let old_id = identity.agent_key_id.ok_or("migration incomplete: current credential has no key ID")?;
    let grant = old.mint(label).await?;
    let new = KeyApi::new(&config.require_server()?, &grant.key);
    let verified = new.me().await?;
    if verified.id != identity.id || verified.agent_key_id.as_deref() != Some(&grant.id) {
        return Err("new key verification did not match the agent and credential; active config unchanged".into());
    }
    storage.install(&grant.key)?;
    if new.revoke(&old_id).await.is_err() {
        // A lost HTTP response can hide a successful revoke. Never restore a dead bearer.
        if old.me().await.is_ok() {
            storage.restore()?;
            return Err("old-key revocation failed; restored the previous active key; the new key may still be live".into());
        }
        return Err("old-key revocation outcome uncertain; verified new key remains active; previous key saved for recovery".into());
    }
    Ok(grant.id)
}
