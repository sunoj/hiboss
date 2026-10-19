// Purpose: Create, rename and fill collections using readable name/id resolution.
// Applies membership changes in order and identifies the first failed item.
use super::{Collection, CollectionArgs, CollectionCommand, CollectionPage, render, resolve};
use crate::client::HiBossClient;
use reqwest::Method;
use serde_json::json;
use std::error::Error;

pub(super) async fn run(
    command: &CollectionCommand,
    args: &CollectionArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    if let CollectionCommand::New { name } = command {
        let mut body = json!({ "name": name });
        if let Some(boss) = &args.boss {
            body["boss"] = json!(boss);
        }
        let value = client
            .mutate_box_collection(Method::POST, &[], Some(body))
            .await?;
        return print_collection(value, args.json);
    }
    run_existing(command, args, client).await
}

async fn run_existing(
    command: &CollectionCommand,
    args: &CollectionArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let (CollectionCommand::Rename { collection, .. }
    | CollectionCommand::Add { collection, .. }
    | CollectionCommand::Rm { collection, .. }) = command
    else {
        return Ok(());
    };
    let page = client.box_collections().await?;
    let ids = resolve(
        &page,
        std::slice::from_ref(collection),
        args.boss.as_deref(),
    )?;
    let id = ids.first().ok_or("collection resolution returned no ID")?;
    match command {
        CollectionCommand::Rename { new_name, .. } => {
            let value = client
                .mutate_box_collection(Method::PATCH, &[id], Some(json!({ "name": new_name })))
                .await?;
            print_collection(value, args.json)
        }
        CollectionCommand::Add { items, .. } | CollectionCommand::Rm { items, .. } => {
            for item in items {
                let method = if matches!(command, CollectionCommand::Add { .. }) {
                    Method::PUT
                } else {
                    Method::DELETE
                };
                client
                    .mutate_box_collection(method, &[id, "items", item], None)
                    .await
                    .map_err(|err| format!("item {item}: {err}"))?;
            }
            let verb = if matches!(command, CollectionCommand::Add { .. }) {
                "added to"
            } else {
                "removed from"
            };
            println!("{} item(s) {verb} {collection} ({id})", items.len());
            Ok(())
        }
        CollectionCommand::New { .. } => Ok(()),
    }
}

fn print_collection(value: serde_json::Value, json: bool) -> Result<(), Box<dyn Error>> {
    let collection: Collection = serde_json::from_value(value)?;
    println!(
        "{}",
        render(
            &CollectionPage {
                collections: vec![collection]
            },
            json
        )?
    );
    Ok(())
}
