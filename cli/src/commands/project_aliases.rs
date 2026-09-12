// Purpose: Parse and execute hiboss project aliases add/remove.
// Exports: AliasArgs and run; depends on clap, the project resolver and HTTP client.
use clap::{Args, Subcommand};
use crate::{client::HiBossClient, session};
use std::error::Error;

#[derive(Debug, Args)]
pub struct AliasArgs {
    #[command(subcommand)]
    pub command: AliasCommand,
}

#[derive(Debug, Subcommand)]
pub enum AliasCommand {
    Add(AliasValue),
    Remove(AliasValue),
}

#[derive(Debug, Args)]
pub struct AliasValue {
    pub alias: String,
    #[arg(long)]
    pub project: Option<String>,
}

pub async fn run(args: &AliasArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let (value, remove) = match &args.command {
        AliasCommand::Add(value) => (value, false),
        AliasCommand::Remove(value) => (value, true),
    };
    let project = value.project.clone().unwrap_or_else(session::project_name);
    client.change_project_alias(&project, &value.alias, remove).await?;
    println!("{}: {} {}", project, if remove { "removed" } else { "added" }, value.alias);
    Ok(())
}
