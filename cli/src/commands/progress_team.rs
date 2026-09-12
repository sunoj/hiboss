// Purpose: Project profiles, aliases and local team.json synchronization.
// Exports: TeamArgs, run.
// Dependencies: clap, colored, crate::client, crate::config, crate::session, crate::team.

#[path = "project_aliases.rs"]
mod project_aliases;

use crate::{
    client::HiBossClient,
    config::Config,
    hiboss_dir,
    hiboss_dir::LocalTeam,
    session,
    team::{ProgressTeamFull, ProgressTeamRequest},
};
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct TeamArgs {
    #[command(subcommand)]
    pub command: TeamCommand,
}

#[derive(Debug, Subcommand)]
pub enum TeamCommand {
    #[command(about = "Show the canonical project profile")]
    Show(ShowArgs),
    #[command(name = "set", alias = "register", about = "Update this project profile")]
    Register(RegisterArgs),
    #[command(hide = true, about = "Upload and set the project avatar")]
    SetAvatar(SetAvatarArgs),
    #[command(about = "Add or remove project aliases")]
    Aliases(project_aliases::AliasArgs),
}

#[derive(Debug, Args)]
pub struct ShowArgs {
    #[arg(long, help = "Project slug or alias (default: origin repository)")]
    pub project: Option<String>,
}

#[derive(Debug, Args)]
pub struct RegisterArgs {
    #[arg(long, help = "Project display name")]
    pub display_name: Option<String>,
    #[arg(long, help = "Handle [a-z0-9_-]{1,32}")]
    pub handle: Option<String>,
    #[arg(long, help = "Short bio")]
    pub bio: Option<String>,
    #[arg(long, help = "Local image file for the team avatar")]
    pub avatar: Option<String>,
    #[arg(long, help = "Project slug or alias (default: origin repository)")]
    pub project: Option<String>,
}

#[derive(Debug, Args)]
pub struct SetAvatarArgs {
    #[arg(value_name = "path", help = "Local image file for the team avatar")]
    pub path: String,
    #[arg(long, help = "Project slug or alias (default: origin repository)")]
    pub project: Option<String>,
}

pub async fn run(
    args: &TeamArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        TeamCommand::Show(a) => run_show(a, config, client).await,
        TeamCommand::Register(a) => run_register(a, config, client).await,
        TeamCommand::SetAvatar(a) => run_set_avatar(a, config, client).await,
        TeamCommand::Aliases(a) => project_aliases::run(a, client).await,
    }
}

async fn run_show(
    args: &ShowArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let project = args.project.clone().unwrap_or_else(session::project_name);
    let team = client.project_profile(&project).await?;
    print_team(&team);
    Ok(())
}

async fn run_register(
    args: &RegisterArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let project = args.project.clone().unwrap_or_else(session::project_name);
    let avatar_url = match &args.avatar {
        Some(path) => Some(client.upload_file(path).await?.url),
        None => None,
    };
    let server_team = client.upsert_progress_team(&project, &ProgressTeamRequest {
        handle: args.handle.clone(), display_name: args.display_name.clone(),
        bio: args.bio.clone(), avatar_url,
    }).await?;
    let existing = hiboss_dir::read_local_team();
    let local_team = LocalTeam {
        handle: server_team.handle.clone(), display_name: server_team.display_name.clone(),
        bio: server_team.bio.clone(),
        avatar: args.avatar.as_ref().map(|_| "avatar.png".to_owned())
            .or_else(|| existing.and_then(|t| t.avatar)),
    };
    hiboss_dir::write_local_team(&local_team)?;
    if let Some(src) = &args.avatar { std::fs::copy(src, hiboss_dir::avatar_png_path())?; }
    let hash = hiboss_dir::team_json_hash().ok_or("cannot hash team.json")?;
    hiboss_dir::write_local_state(&hiboss_dir::LocalState { synced_hash: hash })?;
    print_team(&server_team);
    Ok(())
}

async fn run_set_avatar(
    args: &SetAvatarArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let project = args.project.clone().unwrap_or_else(session::project_name);
    // Update the local team.json avatar field if team.json exists
    if let Some(mut local) = hiboss_dir::read_local_team() {
        local.avatar = Some("avatar.png".to_owned());
        hiboss_dir::write_local_team(&local)?;
    }
    std::fs::copy(&args.path, hiboss_dir::avatar_png_path())?;
    let team = push_local_team(&project, client).await?;
    print_team(&team);
    Ok(())
}

/// Upload avatar (if present), push `team.json` to server, update `state.json`.
async fn push_local_team(
    project: &str,
    client: &HiBossClient,
) -> Result<ProgressTeamFull, Box<dyn Error>> {
    let team = hiboss_dir::read_local_team()
        .ok_or("team.json not found or unreadable")?;
    let hash = hiboss_dir::team_json_hash()
        .ok_or("cannot hash team.json")?;
    let avatar_url = match &team.avatar {
        Some(filename) => {
            let path = hiboss_dir::hiboss_dir().join(filename);
            if path.exists() {
                let p = path.to_str().ok_or("avatar path not valid UTF-8")?;
                Some(client.upload_file(p).await?.url)
            } else {
                None
            }
        }
        None => None,
    };
    let req = ProgressTeamRequest {
        handle: Some(team.handle),
        display_name: Some(team.display_name),
        bio: team.bio,
        avatar_url,
    };
    let result = client.upsert_progress_team(project, &req).await?;
    hiboss_dir::write_local_state(&hiboss_dir::LocalState { synced_hash: hash })?;
    Ok(result)
}

/// Lazy sync: push `team.json` to server only when hash differs from `state.json`.
pub async fn sync_team_to_server(
    project: &str,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    if !hiboss_dir::needs_sync() {
        return Ok(());
    }
    push_local_team(project, client).await?;
    Ok(())
}

fn print_team(team: &ProgressTeamFull) {
    println!("{} @{}", team.display_name.bold(), team.handle.dimmed());
    if let Some(bio) = &team.bio {
        println!("  {}", bio);
    }
    match &team.avatar_url {
        Some(url) => println!("  avatar: {}", url.dimmed()),
        None => println!("  avatar: {}", "(generated identicon)".dimmed()),
    }
    println!("  project: {}", team.project);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_team_to_server_compiles() {
        let client = crate::client::HiBossClient::new("http://localhost:19999", "test-key");
        let _f = sync_team_to_server("myproject", &client);
        drop(_f);
    }

    #[test]
    fn push_local_team_compiles() {
        let client = crate::client::HiBossClient::new("http://localhost:19999", "test-key");
        let _f = push_local_team("myproject", &client);
        drop(_f);
    }
}
