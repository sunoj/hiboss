// Purpose: hiboss progress subcommand — post, list, delete, and team management.
// Exports: ProgressArgs, run.
// Dependencies: clap, colored, crate::client, crate::config, crate::session, crate::types.
#[path = "progress_media.rs"]
mod progress_media;
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
    #[command(about = "Manage team identity for the project timeline")]
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
        ProgressCommand::Team(a) => progress_team::run(a, config, client).await,
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
    let project = args.project.clone().unwrap_or_else(session::project_name);
    let session_id = args.session.clone().or_else(session::read_session_id);
    let mut media: Vec<ProgressMediaItem> = Vec::with_capacity(total);
    let mut alt_idx = 0usize;
    for path in &args.image {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(process_image(path, alt, client).await?);
    }
    for path in &args.video {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(process_video(path, alt, client).await?);
    }
    for url in &args.url {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(url_media_item(url, alt));
    }
    let req = ProgressPostRequest {
        body: args.body.clone(),
        project: Some(project.clone()),
        session_id,
        media: if media.is_empty() { None } else { Some(media) },
        tags: if args.tag.is_empty() { None } else { Some(args.tag.clone()) },
    };
    let post = client.post_progress(&req).await?;
    eprintln!("Posted");
    println!("{}", post.id);
    // Lazy sync: push team.json to server if it changed since last sync.
    let _ = progress_team::sync_team_to_server(&project, client).await;
    maybe_hint_team_register(&project, &post);
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

async fn process_image(
    path: &str,
    alt: Option<String>,
    client: &HiBossClient,
) -> Result<ProgressMediaItem, Box<dyn Error>> {
    if path.to_lowercase().ends_with(".gif") {
        if let Some(tmp) = progress_media::convert_gif_to_mp4(path) {
            let mp4 = tmp.0.to_str().ok_or("temp path is not valid UTF-8")?.to_owned();
            let (dims, dur) = progress_media::probe_video_meta(&mp4);
            let up = client.upload_raw_binary(&mp4, "clip.mp4").await?;
            return Ok(make_item(up.url, "video", "video/mp4", up.size, dims, dur, None, alt));
        }
        eprintln!("Warning: GIF conversion unavailable; uploading GIF as-is (iOS shows a still frame)");
    }
    let dims = progress_media::probe_image_dims(path);
    let up = client.upload_file(path).await?;
    Ok(make_item(up.url, "image", &up.content_type, up.size, dims, None, None, alt))
}

async fn process_video(
    path: &str,
    alt: Option<String>,
    client: &HiBossClient,
) -> Result<ProgressMediaItem, Box<dyn Error>> {
    let (dims, dur) = progress_media::probe_video_meta(path);
    let poster_url = match progress_media::extract_video_poster(path) {
        Some(tmp) => {
            let p = tmp.0.to_str().ok_or("poster path is not valid UTF-8")?.to_owned();
            let result = client.upload_file(&p).await.ok().map(|u| u.url);
            drop(tmp);
            result
        }
        None => None,
    };
    let fname = std::path::Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("video.mp4");
    let up = client.upload_raw_binary(path, fname).await?;
    Ok(make_item(up.url, "video", &up.content_type, up.size, dims, dur, poster_url, alt))
}

fn make_item(
    url: String, kind: &str, content_type: &str, size: u64,
    dims: Option<(u32, u32)>, duration_ms: Option<u64>,
    poster_url: Option<String>, alt: Option<String>,
) -> ProgressMediaItem {
    ProgressMediaItem {
        url, kind: kind.into(), content_type: content_type.into(), size,
        width: dims.map(|(w, _)| w), height: dims.map(|(_, h)| h),
        duration_ms, poster_url, alt,
    }
}

fn url_media_item(url: &str, alt: Option<String>) -> ProgressMediaItem {
    let kind = if url.contains(".mp4") || url.contains(".mov") { "video" } else { "image" };
    ProgressMediaItem {
        url: url.to_owned(), kind: kind.into(),
        content_type: progress_media::mime_for_path(url).into(),
        size: 0, width: None, height: None, duration_ms: None, poster_url: None, alt,
    }
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
    println!("{} · {} · {}", identity.cyan(), rel.dimmed(), agent.dimmed());
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
