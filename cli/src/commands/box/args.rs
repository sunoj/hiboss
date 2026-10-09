// Purpose: clap layout for Box ingestion, scoped reads and author-owned deletion.
// Exports: BoxArgs, BoxCommand and typed options; depends on clap and BoxKind.
use crate::box_types::{BoxBy, BoxFilter, BoxKind};
use clap::{Args, Subcommand};
use std::path::PathBuf;

#[derive(Debug, Args)]
pub struct BoxArgs {
    #[command(subcommand)]
    pub command: BoxCommand,
}

#[derive(Debug, Subcommand)]
pub enum BoxCommand {
    #[command(about = "Add text, a URL or a file to a boss's Box")]
    Add(AddArgs),
    #[command(about = "Read the newest Box item and save its media")]
    Latest(LatestArgs),
    #[command(about = "List recent Box reference items")]
    List(ListArgs),
    #[command(about = "Search Box reference text, notes, URLs and tags")]
    Search(SearchArgs),
    #[command(about = "Read one Box item and save its media")]
    Show(ShowArgs),
    #[command(about = "Delete a Box item (agents can delete only their own items)")]
    Rm(RmArgs),
}

#[derive(Debug, Args)]
pub struct AddArgs {
    #[arg(value_name = "TEXT|URL|PATH")]
    pub content: String,
    #[arg(
        long,
        help = "Target boss ID or name (required for agents serving several bosses)"
    )]
    pub boss: Option<String>,
    #[arg(long)]
    pub note: Option<String>,
    #[arg(long)]
    pub project: Option<String>,
    #[arg(long, help = "Tag to apply (repeatable)")]
    pub tag: Vec<String>,
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Default, Args)]
pub struct Filters {
    #[arg(long, value_enum)]
    pub kind: Option<BoxKind>,
    #[arg(long, help = "Filter by boss ID or name")]
    pub boss: Option<String>,
    #[arg(long, value_enum, help = "Filter by who added the item (default: all)")]
    pub by: Option<BoxBy>,
    #[arg(long, help = "Items since 1h, 2d or an ISO timestamp")]
    pub since: Option<String>,
    #[arg(long)]
    pub project: Option<String>,
}

#[derive(Debug, Args)]
pub struct LatestArgs {
    #[command(flatten)]
    pub filters: Filters,
    #[command(flatten)]
    pub output: SavedOutput,
}

#[derive(Debug, Default, Args)]
pub struct SavedOutput {
    #[arg(long, help = "Save media in this directory (default: per-profile Box cache)")]
    pub save: Option<PathBuf>,
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct ListArgs {
    #[command(flatten)]
    pub filters: Filters,
    #[arg(long, value_parser = clap::value_parser!(u32).range(1..=100))]
    pub limit: Option<u32>,
    #[arg(long, help = "Opaque next_cursor from a previous page")]
    pub cursor: Option<String>,
    #[arg(long)]
    pub json: bool,
}

impl ListArgs {
    pub fn filter(&self) -> BoxFilter<'_> {
        BoxFilter {
            limit: self.limit,
            cursor: self.cursor.as_deref(),
            ..self.filters.filter()
        }
    }
}

impl Filters {
    pub fn filter(&self) -> BoxFilter<'_> {
        BoxFilter {
            kind: self.kind,
            since: self.since.as_deref(),
            project: self.project.as_deref(),
            boss: self.boss.as_deref(),
            by: self.by,
            ..BoxFilter::default()
        }
    }
}

#[derive(Debug, Args)]
pub struct SearchArgs {
    pub query: String,
    #[command(flatten)]
    pub list: ListArgs,
}

#[derive(Debug, Args)]
pub struct ShowArgs {
    pub id: String,
    #[command(flatten)]
    pub output: SavedOutput,
}

#[derive(Debug, Args)]
pub struct RmArgs {
    pub id: String,
    #[arg(long, help = "Permanently remove the item and its media")]
    pub purge: bool,
}
