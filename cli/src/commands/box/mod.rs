// Purpose: Dispatch Box ingestion, reads, media saving and deletion.
// Exports: BoxArgs, BoxCommand, run; depends on the existing client and configuration.
mod args;
#[cfg(test)]
mod http_media_tests;
#[cfg(test)]
mod http_tests;
mod input;
mod media;
#[cfg(test)]
mod mock;
mod output;
#[cfg(test)]
mod tests;

use crate::{
    box_types::{BoxItem, BoxMetadata},
    client::HiBossClient,
    config::Config,
};
use args::{AddArgs, ListArgs, SavedOutput};
pub use args::{BoxArgs, BoxCommand};
use std::error::Error;

pub async fn run(args: &BoxArgs, config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        BoxCommand::Add(args) => {
            let item = add(args, client).await?;
            output::print_item(&item, None, args.json)
        }
        BoxCommand::Latest(args) => {
            let item = client.latest_box_item(&args.filters.filter()).await?;
            display_saved(&item, &args.output, config, client).await
        }
        BoxCommand::List(args) => list(args, None, client).await,
        BoxCommand::Search(args) => list(&args.list, Some(&args.query), client).await,
        BoxCommand::Show(args) => {
            let item = client.show_box_item(&args.id).await?;
            display_saved(&item, &args.output, config, client).await
        }
        BoxCommand::Rm(args) => {
            client.remove_box_item(&args.id, args.purge).await?;
            eprintln!("Deleted");
            Ok(())
        }
    }
}

async fn add(args: &AddArgs, client: &HiBossClient) -> Result<BoxItem, Box<dyn Error>> {
    if args.note.as_ref().is_some_and(|note| note.len() > 16 * 1024) {
        return Err("note exceeds 16 KB".into());
    }
    let input = input::detect(&args.content)?;
    let metadata = BoxMetadata {
        boss: args.boss.as_deref(),
        text: (input == input::Input::Text).then_some(args.content.as_str()),
        url: (input == input::Input::Link).then_some(args.content.as_str()),
        note: args.note.as_deref(),
        project: args.project.as_deref(),
        tags: &args.tag,
        source: "cli",
    };
    let file = match &input {
        input::Input::File(path, mime) => Some((path.as_path(), mime.as_str())),
        _ => None,
    };
    let item = client.add_box_item(&metadata, file).await?;
    eprintln!("Added");
    Ok(item)
}

async fn display_saved(
    item: &BoxItem,
    output: &SavedOutput,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let path = media::save_media(client, item, config, output.save.as_deref()).await?;
    output::print_item(item, path.as_deref(), output.json)
}

async fn list(args: &ListArgs, query: Option<&str>, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let page = client.list_box_items(&args.filter(), query).await?;
    if page.items.is_empty() {
        eprintln!("No Box items found");
    }
    for item in &page.items {
        output::print_item(item, None, args.json)?;
    }
    if let Some(cursor) = page.next_cursor {
        eprintln!("next_cursor: {cursor}");
    }
    Ok(())
}
