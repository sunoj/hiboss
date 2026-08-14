// Purpose: hiboss progress team subcommands — show, register, and set-avatar.
// Exports: TeamArgs, run.
// Dependencies: clap, colored, crate::client, crate::config, crate::session, crate::team.

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
    #[command(about = "Show the registered team for this project")]
    Show(ShowArgs),
    #[command(about = "Register or update the team identity for this project")]
    Register(RegisterArgs),
    #[command(about = "Upload and set the team avatar")]
    SetAvatar(SetAvatarArgs),
}

#[derive(Debug, Args)]
pub struct ShowArgs {
    #[arg(long, help = "Project name (default: git-root basename)")]
    pub project: Option<String>,
}

#[derive(Debug, Args)]
pub struct RegisterArgs {
    #[arg(long, help = "Display name (default: project name)")]
    pub display_name: Option<String>,
    #[arg(long, help = "Handle [a-z0-9_-]{1,32} (default: slugified project name)")]
    pub handle: Option<String>,
    #[arg(long, help = "Short bio")]
    pub bio: Option<String>,
    #[arg(long, help = "Local image file for the team avatar")]
    pub avatar: Option<String>,
    #[arg(long, help = "Project name (default: git-root basename)")]
    pub project: Option<String>,
}

#[derive(Debug, Args)]
pub struct SetAvatarArgs {
    #[arg(value_name = "path", help = "Local image file for the team avatar")]
    pub path: String,
    #[arg(long, help = "Project name (default: git-root basename)")]
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
    }
}

async fn run_show(
    args: &ShowArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let project = args.project.clone().unwrap_or_else(session::project_name);
    // Prefer the local team.json; fall back to server query when absent.
    if let Some(local) = hiboss_dir::read_local_team() {
        let sync_label = if hiboss_dir::needs_sync() { "needs sync" } else { "in sync" };
        println!("{} @{}", local.display_name.bold(), local.handle.dimmed());
        if let Some(bio) = &local.bio {
            println!("  {}", bio);
        }
        match &local.avatar {
            Some(f) => println!("  avatar: {}", f.dimmed()),
            None => println!("  avatar: {}", "(none)".dimmed()),
        }
        println!("  project: {}", project);
        println!("  sync: {}", sync_label.dimmed());
        return Ok(());
    }
    // No local team.json — query server
    let resp = client.list_progress_teams().await?;
    match resp.teams.iter().find(|t| t.project == project) {
        Some(team) => print_team(team),
        None => {
            let slug = slugify(&project);
            eprintln!("No team registered for project \"{}\".", project);
            eprintln!(
                "Run: hiboss progress team register --display-name \"{}\" --handle \"{}\"",
                project.replace('"', ""),
                slug
            );
        }
    }
    Ok(())
}

async fn run_register(
    args: &RegisterArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let project = args.project.clone().unwrap_or_else(session::project_name);
    let display_name = args.display_name.clone().unwrap_or_else(|| project.clone());
    let handle = args.handle.clone().unwrap_or_else(|| slugify(&project));

    let local_team = LocalTeam {
        handle,
        display_name,
        bio: args.bio.clone(),
        avatar: args.avatar.as_ref().map(|_| "avatar.png".to_owned()),
    };
    hiboss_dir::write_local_team(&local_team)?;
    if let Some(ref src) = args.avatar {
        std::fs::copy(src, hiboss_dir::avatar_png_path())?;
    }
    let server_team = push_local_team(&project, client).await?;
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

/// Convert an arbitrary string into a handle slug matching `^[a-z0-9_-]{1,32}$`.
/// Non-alphanumeric, non-underscore characters collapse to a single dash; leading
/// and trailing dashes are trimmed; the result is capped at 32 characters.
pub(crate) fn slugify(s: &str) -> String {
    let mut result = String::with_capacity(s.len().min(32));
    let mut prev_dash = false;
    for c in s.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() || c == '_' {
            result.push(c);
            prev_dash = false;
        } else if !result.is_empty() && !prev_dash {
            result.push('-');
            prev_dash = true;
        }
    }
    let trimmed = result.trim_end_matches('-').to_owned();
    trimmed.chars().take(32).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugify_simple_name() {
        assert_eq!(slugify("my-project"), "my-project");
    }

    #[test]
    fn slugify_spaces_become_dashes() {
        assert_eq!(slugify("My Project"), "my-project");
    }

    #[test]
    fn slugify_consecutive_separators_collapse() {
        assert_eq!(slugify("my  project"), "my-project");
    }

    #[test]
    fn slugify_preserves_underscore() {
        assert_eq!(slugify("my_project"), "my_project");
    }

    #[test]
    fn slugify_leading_separator_stripped() {
        assert_eq!(slugify("-foo"), "foo");
    }

    #[test]
    fn slugify_no_trailing_dash() {
        let s = slugify("project!");
        assert!(!s.ends_with('-'), "got: {s}");
    }

    #[test]
    fn slugify_truncates_at_32() {
        let long = "a".repeat(40);
        assert_eq!(slugify(&long).len(), 32);
    }

    #[test]
    fn slugify_special_chars_collapse() {
        assert_eq!(slugify("hello@world.com"), "hello-world-com");
    }

    #[test]
    fn slugify_empty_string() {
        assert_eq!(slugify(""), "");
    }

    #[test]
    fn slugify_default_handle_for_project_name() {
        // Mirrors how RegisterArgs derives a default handle.
        assert_eq!(slugify("hiboss-server"), "hiboss-server");
        assert_eq!(slugify("HiBoss Server"), "hiboss-server");
    }

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
