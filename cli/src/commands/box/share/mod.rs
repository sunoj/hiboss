// Purpose: Public share links for Box items: create, list and revoke, plus `box add --share`.
// Exports: share argument types, wire types and command helpers; depends on the Box client.
#[cfg(test)]
mod http_tests;
pub(crate) mod ttl;

use super::output::single_line;
use crate::client::HiBossClient;
use clap::Args;
use serde::{Deserialize, Serialize};
use std::error::Error;

pub(crate) const VISIBILITY: &str =
    "Anyone with the link can view the item until it expires or is revoked.";

#[derive(Debug, Args)]
pub struct ShareArgs {
    #[arg(value_name = "ITEM_ID")]
    pub id: String,
    #[arg(long, value_parser = ttl::parse, help = "Link lifetime: <n>h, <n>d or seconds, 1h..30d (default 7d)")]
    pub ttl: Option<u64>,
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct SharesArgs {
    #[arg(value_name = "ITEM_ID")]
    pub id: String,
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct UnshareArgs {
    #[arg(value_name = "SHARE_ID")]
    pub id: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoxShare {
    pub id: String,
    pub item_id: String,
    pub url: String,
    pub expires_at: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ShareRecord {
    pub id: String,
    pub item_id: String,
    pub created_at: String,
    pub expires_at: String,
    pub revoked_at: Option<String>,
    pub created_by: String,
    pub view_count: u64,
    pub last_viewed_at: Option<String>,
    pub active: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct BoxShareList {
    pub shares: Vec<ShareRecord>,
}

/// Creates a share and prints its URL on stdout (`share: <url>` when `labelled`).
pub(super) async fn create(
    client: &HiBossClient,
    item: &str,
    ttl: Option<u64>,
    json: bool,
    labelled: bool,
) -> Result<(), Box<dyn Error>> {
    let share = client.create_box_share(item, ttl).await?;
    println!("{}", render_created(&share, json, labelled)?);
    eprintln!(
        "Share link expires {}. {VISIBILITY}",
        single_line(&share.expires_at)
    );
    Ok(())
}

pub(super) async fn list(args: &SharesArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let list = client.list_box_shares(&args.id).await?;
    if args.json {
        println!("{}", serde_json::to_string(&list)?);
    } else if list.shares.is_empty() {
        eprintln!("No share links for this item");
    } else {
        println!("{}", render_table(&list.shares));
    }
    Ok(())
}

pub(super) async fn revoke(
    args: &UnshareArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    client.revoke_box_share(&args.id).await?;
    eprintln!("Revoked");
    Ok(())
}

pub(super) fn render_created(
    share: &BoxShare,
    json: bool,
    labelled: bool,
) -> Result<String, Box<dyn Error>> {
    if json {
        return Ok(serde_json::to_string(share)?);
    }
    let url = single_line(&share.url);
    Ok(if labelled {
        format!("share: {url}")
    } else {
        url
    })
}

pub(super) fn render_table(shares: &[ShareRecord]) -> String {
    let mut lines = vec![format!(
        "{:<36}  {:<20}  {:<20}  {:>5}  ACTIVE",
        "ID", "CREATED", "EXPIRES", "VIEWS"
    )];
    lines.extend(shares.iter().map(|share| {
        format!(
            "{:<36}  {:<20}  {:<20}  {:>5}  {}",
            single_line(&share.id),
            single_line(&share.created_at),
            single_line(&share.expires_at),
            share.view_count,
            if share.active { "yes" } else { "no" }
        )
    }));
    lines.join("\n")
}
