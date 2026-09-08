// Purpose: Expose agent-facing panel validation, publication, and reads.
// Exports: PanelArgs, PanelCommand, and run.
// Dependencies: clap, ring, serde_json, panel validation, client, and config.

#[path = "panel/validation.rs"]
mod validation;
#[path = "panel/json.rs"]
mod json;
#[path = "panel/stream.rs"]
mod stream;

use crate::client::{HiBossClient, PanelPublishResponse};
use clap::{Args, Subcommand};
use ring::digest::{digest, SHA256};
use serde_json::{json, Value};
use std::error::Error;
use std::path::PathBuf;

#[derive(Debug, Args)]
pub struct PanelArgs {
    #[command(subcommand)]
    pub command: PanelCommand,
}

#[derive(Debug, Subcommand)]
pub enum PanelCommand {
    #[command(about = "Read the built-in dynamic notification and test report delivery guide")]
    Guide,
    #[command(about = "Validate a panel publication document locally")]
    Validate(PanelFileArgs),
    #[command(about = "Publish a panel publication document")]
    Publish(PanelPublishArgs),
    #[command(about = "List panels visible to this agent")]
    List(PanelListArgs),
    #[command(about = "Show a panel and its current definition")]
    Show(PanelShowArgs),
    #[command(about = "Stream partial task state from stdin to a live panel")]
    Stream(stream::PanelStreamArgs),
    #[command(about = "Read the authoritative producer checkpoint")]
    State(PanelShowArgs),
    #[command(about = "Apply a v2 pause/resume/complete/fail/cancel command from a JSON file")]
    Lifecycle(PanelControlArgs),
    #[command(about = "Replace the definition with a version-checked v2 command file")]
    Definition(PanelControlArgs),
}

#[derive(Debug, Args)]
pub struct PanelControlArgs {
    pub id: String,
    pub file: PathBuf,
    #[arg(long, help = "Stable key for this exact command; reuse when retrying")]
    pub idempotency_key: String,
}

#[derive(Debug, Args)]
pub struct PanelFileArgs { #[arg(value_name = "FILE")] pub file: PathBuf }

#[derive(Debug, Args)]
pub struct PanelPublishArgs {
    #[arg(value_name = "FILE")]
    pub file: PathBuf,
    #[arg(long, value_name = "KEY", help = "Idempotency key; defaults to a stable key derived from the file")]
    pub idempotency_key: Option<String>,
}

#[derive(Debug, Args)]
pub struct PanelListArgs {
    #[arg(long, help = "Opaque cursor returned by a previous list response")]
    pub cursor: Option<String>,
    #[arg(long, help = "Print JSON instead of a human-readable summary")]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct PanelShowArgs {
    #[arg(value_name = "ID")] pub id: String,
    #[arg(long, help = "Print JSON instead of a human-readable summary")] pub json: bool,
}

pub async fn run(args: &PanelArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        PanelCommand::Guide => { println!("{}", crate::commands::setup_agents::PANEL_GUIDE); Ok(()) },
        PanelCommand::Validate(arguments) => run_validate(arguments),
        PanelCommand::Publish(arguments) => run_publish(arguments, client).await,
        PanelCommand::List(arguments) => run_list(arguments, client).await,
        PanelCommand::Show(arguments) => run_show(arguments, client).await,
        PanelCommand::Stream(arguments) => stream::run(arguments, client).await,
        PanelCommand::State(arguments) => { println!("{}", serde_json::to_string_pretty(&client.panel_state(&arguments.id).await?)?); Ok(()) },
        PanelCommand::Lifecycle(arguments) => run_control(arguments, client, "lifecycle").await,
        PanelCommand::Definition(arguments) => run_control(arguments, client, "definition").await,
    }
}

async fn run_control(args: &PanelControlArgs, client: &HiBossClient, action: &str) -> Result<(), Box<dyn Error>> {
    let body: Value = serde_json::from_slice(&std::fs::read(&args.file)?)?;
    if body.get("protocolVersion").and_then(Value::as_u64) != Some(2) { return Err("control requires protocolVersion 2".into()); }
    let result = client.panel_command(&args.id, action, &body, &args.idempotency_key).await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    if result.get("status").and_then(Value::as_str) == Some("pending") {
        return Err("result is still saving; retry the same file and idempotency key".into());
    }
    Ok(())
}

pub fn run_validate(args: &PanelFileArgs) -> Result<(), Box<dyn Error>> {
    validation::validate_file(&args.file)?;
    println!("valid");
    Ok(())
}

async fn run_publish(args: &PanelPublishArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let body = validation::validate_file(&args.file)?;
    let key = args.idempotency_key.clone().unwrap_or_else(|| stable_key(&body));
    let response = client.publish_panel(&body, &key).await?;
    println!("{}", serde_json::to_string(&publish_output(&response))?);
    Ok(())
}

async fn run_list(args: &PanelListArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.list_panels(args.cursor.as_deref()).await?;
    if args.json { println!("{}", serde_json::to_string_pretty(&response)?); return Ok(()); }
    let panels = response.get("panels").and_then(Value::as_array).or_else(|| response.as_array());
    let Some(panels) = panels else { println!("{}", serde_json::to_string_pretty(&response)?); return Ok(()); };
    if panels.is_empty() { eprintln!("No panels found"); return Ok(()); }
    println!("{:<24} {:<28} {:<10} {}", "ID", "TITLE", "REVISION", "STATUS");
    for panel in panels { println!("{:<24} {:<28} {:<10} {}", field(panel, &["panelId", "id"]), field(panel, &["title"]), field(panel, &["definitionRevision"]), field(&panel["lifecycle"], &["taskState"])); }
    Ok(())
}

async fn run_show(args: &PanelShowArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let response = client.get_panel(&args.id).await?;
    if args.json { println!("{}", serde_json::to_string_pretty(&response)?); return Ok(()); }
    let Some(object) = response.as_object() else { println!("{}", serde_json::to_string_pretty(&response)?); return Ok(()); };
    for (key, label) in [("panelId", "Panel ID"), ("title", "Title"), ("definitionRevision", "Definition revision"), ("metadataVersion", "Metadata version"), ("status", "Status"), ("createdAt", "Created at")] { if let Some(value) = object.get(key) { println!("{label}: {}", display_value(value)); } }
    println!("Definition:");
    println!("{}", serde_json::to_string_pretty(&response)?);
    Ok(())
}

fn publish_output(response: &PanelPublishResponse) -> Value { json!({"panelId": response.panel_id, "definitionRevision": response.definition_revision}) }
fn field(value: &Value, keys: &[&str]) -> String { keys.iter().find_map(|key| value.get(*key).map(display_value)).unwrap_or_else(|| "-".into()) }
fn display_value(value: &Value) -> String { value.as_str().map(str::to_owned).unwrap_or_else(|| value.to_string()) }
fn stable_key(value: &Value) -> String { let bytes = serde_json::to_vec(value).unwrap_or_default(); let hash = digest(&SHA256, &bytes); let hex = hash.as_ref().iter().map(|byte| format!("{byte:02x}")).collect::<String>(); format!("hiboss-panel-{hex}") }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_key_is_repeatable_for_same_document() { let value = json!({"title":"panel"}); assert_eq!(stable_key(&value), stable_key(&value)); }

    #[test]
    fn publish_output_contains_only_resume_ids() { let response = PanelPublishResponse { panel_id: "panel_1".into(), definition_revision: 3, extra: Default::default() }; assert_eq!(publish_output(&response), json!({"panelId":"panel_1","definitionRevision":3})); }

    #[test]
    fn field_uses_first_available_alias() { assert_eq!(field(&json!({"id":"panel_1"}), &["panelId", "id"]), "panel_1"); }
}
