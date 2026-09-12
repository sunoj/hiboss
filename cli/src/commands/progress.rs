// Purpose: hiboss progress subcommand — post, list, delete, and team management.
// Exports: ProgressArgs, run.
// Dependencies: clap, colored, crate::client, crate::config, crate::session, crate::types.
#[path = "progress_media.rs"]
mod progress_media;
#[path = "progress_upload.rs"]
mod progress_upload;
use progress_upload::collect_media;
#[cfg(test)]
use progress_upload::{make_item, url_media_item};
#[path = "progress_team.rs"]
pub mod progress_team;
#[cfg(test)]
#[path = "progress_test.rs"]
mod tests;
use crate::{
    client::HiBossClient,
    config::Config,
    hiboss_dir,
    session,
    types::{ProgressCursor, ProgressMediaItem, ProgressPost, ProgressPostRequest},
};
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

#[derive(Debug, Args)]
pub struct ProgressArgs {
    #[command(subcommand)]
    pub command: ProgressCommand,
}

#[derive(Debug, Subcommand)]
pub enum ProgressCommand {
    #[command(about = "Post a progress update to the project timeline")]
    Post(PostArgs),
    #[command(about = "List recent progress posts")]
    List(ListArgs),
    #[command(about = "Delete a progress post")]
    Rm(RmArgs),
    #[command(hide = true, about = "Deprecated alias for hiboss project")]
    Team(progress_team::TeamArgs),
}

#[derive(Debug, Args)]
pub struct PostArgs {
    #[arg(value_name = "body")]
    pub body: String,
    #[arg(long, help = "Local image to attach (repeatable)")]
    pub image: Vec<String>,
    #[arg(long, help = "Local video to attach (repeatable)")]
    pub video: Vec<String>,
    #[arg(long = "url", help = "Pre-uploaded attachment URL (repeatable)")]
    pub url: Vec<String>,
    #[arg(long, help = "Project name (default: git-root basename)")]
    pub project: Option<String>,
    #[arg(long, help = "Session ID (default: current session)")]
    pub session: Option<String>,
    #[arg(long, help = "Tag to apply (repeatable)")]
    pub tag: Vec<String>,
    #[arg(long, help = "Alt text for media items in declaration order (repeatable)")]
    pub alt: Vec<String>,
    #[arg(long = "agent", help = "Override detected agent label (max 64 chars)")]
    pub agent: Option<String>,
    #[arg(long = "model", help = "Override detected model name (max 64 chars)")]
    pub model: Option<String>,
}

#[derive(Debug, Args)]
pub struct ListArgs {
    #[arg(long, help = "Filter by project name")]
    pub project: Option<String>,
    #[arg(long, help = "Maximum posts to return")]
    pub limit: Option<u32>,
    #[arg(long, value_name = "CURSOR_JSON", help = "Return posts older than this JSON cursor from a previous page")]
    pub before: Option<ProgressCursor>,
    #[arg(long, help = "Print raw JSON instead of human-readable feed")]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct RmArgs {
    #[arg(value_name = "id")]
    pub id: String,
}

pub async fn run(
    args: &ProgressArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        ProgressCommand::Post(a) => run_post(a, config, client).await,
        ProgressCommand::List(a) => run_list(a, config, client).await,
        ProgressCommand::Rm(a) => run_rm(a, config, client).await,
        ProgressCommand::Team(a) => {
            eprintln!("Deprecated: use `hiboss project` instead of `hiboss progress team`.");
            progress_team::run(a, config, client).await
        },
    }
}

async fn run_post(
    args: &PostArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let total = args.image.len() + args.video.len() + args.url.len();
    if total > 4 {
        return Err(format!("too many media items: {total} (max 4)").into());
    }
    let project = session::resolve_project(args.project.as_deref());
    let session_id = args.session.clone().or_else(session::read_session_id);
    let attr = crate::attribution::detect();
    let agent_label = args.agent.clone().or(attr.agent_label);
    let model = args.model.clone().or(attr.model);
    if agent_label.as_deref().map_or(false, |v| v.len() > 64) { return Err("--agent exceeds 64 chars".into()); }
    if model.as_deref().map_or(false, |v| v.len() > 64) { return Err("--model exceeds 64 chars".into()); }
    let media = collect_media(args, client).await?;
    let req = ProgressPostRequest {
        body: args.body.clone(),
        project: Some(project.slug.clone()),
        project_identity: Some(project),
        session_id,
        media: if media.is_empty() { None } else { Some(media) },
        tags: if args.tag.is_empty() { None } else { Some(args.tag.clone()) },
        agent_label,
        model,
    };
    let post = client.post_progress(&req).await?;
    eprintln!("Posted");
    println!("{}", post.id);
    // Lazy sync: push team.json to server if it changed since last sync.
    let _ = progress_team::sync_team_to_server(&post.project, client).await;
    maybe_hint_team_register(&post.project, &post);
    Ok(())
}

/// Print a one-line team-registration hint to stderr when the server reports an
/// unregistered team and no local team.json is present. Never errors.
fn maybe_hint_team_register(project: &str, post: &ProgressPost) {
    let unregistered = post.team.as_ref().map_or(false, |t| !t.registered);
    if !unregistered || hiboss_dir::team_json_path().exists() {
        return;
    }
    eprintln!(
        "Run: hiboss progress team register --display-name \"{}\"",
        project.replace('"', "")
    );
}

async fn run_list(
    args: &ListArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let resp = client
        .list_progress(args.project.as_deref(), args.limit, args.before.as_ref())
        .await?;
    if args.json {
        println!("{}", serde_json::to_string_pretty(&resp)?);
        return Ok(());
    }
    if resp.posts.is_empty() {
        eprintln!("No posts found");
        return Ok(());
    }
    for post in &resp.posts {
        print_post(post);
    }
    Ok(())
}

async fn run_rm(
    args: &RmArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    client.delete_progress(&args.id).await?;
    eprintln!("Deleted {}", args.id);
    Ok(())
}

fn print_post(post: &ProgressPost) {
    let rel = relative_time(&post.created_at);
    let agent = post.agent_name.as_deref().unwrap_or(&post.agent_id);
    let identity = post.team.as_ref().map(|t| {
        format!("{} @{}", t.display_name, t.handle)
    }).unwrap_or_else(|| post.project.clone());
    let chip = [post.agent_label.as_deref(), post.model.as_deref()].into_iter().flatten().collect::<Vec<_>>().join(" ");
    let chip_part = if chip.is_empty() { String::new() } else { format!(" · {}", chip.dimmed()) };
    println!("{} · {} · {}{}", identity.cyan(), rel.dimmed(), agent.dimmed(), chip_part);
    println!("  {}", post.body);
    for item in &post.media {
        let marker = match item.kind.as_str() {
            "video" => match item.duration_ms {
                Some(ms) => format!("[video {:.1}s]", ms as f64 / 1000.0),
                None => "[video]".to_owned(),
            },
            _ => "[image]".to_owned(),
        };
        println!("  {}", marker.dimmed());
    }
    if !post.tags.is_empty() {
        let tags = post.tags.iter().map(|t| format!("#{t}")).collect::<Vec<_>>().join(" ");
        println!("  {}", tags.dimmed());
    }
    println!();
}

fn relative_time(iso: &str) -> String {
    let now = OffsetDateTime::now_utc();
    let Ok(then) = OffsetDateTime::parse(iso, &Rfc3339) else {
        return iso.to_owned();
    };
    let secs = (now - then).whole_seconds().max(0);
    if secs < 60 {
        return "just now".to_owned();
    }
    let mins = secs / 60;
    if mins < 60 {
        return format!("{mins}m ago");
    }
    let hrs = mins / 60;
    if hrs < 24 {
        return format!("{hrs}h ago");
    }
    format!("{}d ago", hrs / 24)
}
