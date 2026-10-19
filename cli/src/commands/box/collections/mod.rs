// Purpose: Resolve existing Box collections and render their readable names and counts.
// Exports: collection arguments, response types and command helpers; depends on the Box client.
#[cfg(test)]
mod http_tests;
#[cfg(test)]
mod tests;

use crate::{box_types::BoxItem, client::HiBossClient};
use clap::Args;
use serde::{Deserialize, Serialize};
use std::error::Error;

#[derive(Debug, Args)]
pub struct CollectionArgs {
    #[arg(long)]
    pub boss: Option<String>,
    #[arg(long)]
    pub json: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Collection {
    pub id: String,
    pub boss_id: String,
    pub boss_name: String,
    pub name: String,
    pub item_count: u64,
    pub cover_item_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct CollectionPage {
    pub collections: Vec<Collection>,
}

pub(super) async fn run(args: &CollectionArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let mut page = client.box_collections().await?;
    page.collections
        .retain(|collection| matches_boss(collection, args.boss.as_deref()));
    println!("{}", render(&page, args.json)?);
    Ok(())
}

fn matches_boss(collection: &Collection, boss: Option<&str>) -> bool {
    boss.is_none_or(|boss| collection.boss_id == boss || collection.boss_name.eq_ignore_ascii_case(boss))
}

pub(super) fn resolve(
    page: &CollectionPage,
    requested: &[String],
    boss: Option<&str>,
) -> Result<Vec<String>, Box<dyn Error>> {
    let available: Vec<&Collection> = page
        .collections
        .iter()
        .filter(|collection| matches_boss(collection, boss))
        .collect();
    let mut ids = Vec::new();
    for name in requested {
        let collection = resolve_one(&available, name)?;
        if !ids.contains(&collection.id) {
            ids.push(collection.id.clone());
        }
    }
    Ok(ids)
}

fn resolve_one<'a>(available: &[&'a Collection], name: &str) -> Result<&'a Collection, Box<dyn Error>> {
    if let Some(collection) = available.iter().find(|collection| collection.id == name) {
        return Ok(collection);
    }
    let matches: Vec<&Collection> = available
        .iter()
        .copied()
        .filter(|collection| collection.name.to_lowercase() == name.to_lowercase())
        .collect();
    match matches.as_slice() {
        [collection] => Ok(collection),
        [] => Err(format!(
            "Unknown collection {name}; valid names: {}",
            available
                .iter()
                .map(|c| c.name.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        )
        .into()),
        _ => Err(format!(
            "Ambiguous collection {name}; choices: {}",
            matches
                .iter()
                .map(|c| format!("{} ({}, {})", c.name, c.boss_name, c.id))
                .collect::<Vec<_>>()
                .join(", ")
        )
        .into()),
    }
}

pub(super) async fn for_items(
    items: &[BoxItem],
    json: bool,
    client: &HiBossClient,
) -> Result<Vec<Collection>, Box<dyn Error>> {
    if json || items.iter().all(|item| item.collection_ids.is_empty()) {
        return Ok(Vec::new());
    }
    Ok(client.box_collections().await?.collections)
}

pub(super) fn names(item: &BoxItem, collections: &[Collection]) -> String {
    item.collection_ids
        .iter()
        .map(|id| {
            super::output::single_line(
                collections
                    .iter()
                    .find(|c| c.id == *id)
                    .map_or(id.as_str(), |c| c.name.as_str()),
            )
        })
        .collect::<Vec<_>>()
        .join(", ")
}

pub(super) fn render(page: &CollectionPage, json: bool) -> Result<String, Box<dyn Error>> {
    if json {
        return Ok(serde_json::to_string(page)?);
    }
    Ok(page
        .collections
        .iter()
        .map(|c| {
            format!(
                "{}  {}  {}  boss: {} ({})",
                super::output::single_line(&c.id),
                super::output::single_line(&c.name),
                c.item_count,
                super::output::single_line(&c.boss_name),
                super::output::single_line(&c.boss_id)
            )
        })
        .collect::<Vec<_>>()
        .join("\n"))
}
