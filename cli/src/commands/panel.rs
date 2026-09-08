// Purpose: Expose agent-facing panel validation, publication, and reads.
// Exports: PanelArgs, PanelCommand, and run.
// Dependencies: clap, ring, serde_json, panel validation, client, and config.

#[path = "panel/validation.rs"]
mod validation;
#[path = "panel/json.rs"]
mod json;
#[path = "panel/stream.rs"]
mod stream;
#[path = "panel/update.rs"]
mod update;
#[path = "panel/control.rs"]
mod control;
#[path = "panel/relay_helpers.rs"]
mod relay_helpers;
#[path = "panel/transport.rs"]
mod transport;

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
    #[command(about = "Apply one merged task observation and release the producer lease")]
    Update(update::PanelUpdateArgs),
    #[command(about = "Read the authoritative producer checkpoint")]
    State(PanelShowArgs),
    #[command(about = "Check panel protocol, session, boss, ticket, and relay subscription")]
    Doctor,
    #[command(about = "Apply a v2 pause/resume/complete/fail/cancel command from a JSON file")]
    Lifecycle(PanelControlArgs),
    #[command(about = "Replace the definition with a version-checked v2 command file")]
    Definition(PanelControlArgs),
    #[command(about = "Complete a panel using current server CAS values")]
    Complete(control::PanelLifecycleArgs),
    #[command(about = "Fail a panel using current server CAS values")]
    Fail(control::PanelLifecycleArgs),
    #[command(about = "Cancel a panel using current server CAS values")]
    Cancel(control::PanelLifecycleArgs),
    #[command(about = "Pause a panel using current server CAS values")]
    Pause(control::PanelLifecycleArgs),
    #[command(about = "Resume a panel using current server CAS values")]
    Resume(control::PanelLifecycleArgs),
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
    #[arg(long, help = "Execution identifier included in the default idempotency key")]
    pub run_id: Option<String>,
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
        PanelCommand::Update(arguments) => update::run(arguments, client).await,
        PanelCommand::State(arguments) => { println!("{}", serde_json::to_string_pretty(&client.panel_state(&arguments.id).await?)?); Ok(()) },
        PanelCommand::Doctor => run_doctor(client).await,
        PanelCommand::Lifecycle(arguments) => run_control(arguments, client, "lifecycle").await,
        PanelCommand::Definition(arguments) => run_control(arguments, client, "definition").await,
        PanelCommand::Complete(arguments) => control::run_shortcut("complete", arguments, client).await,
        PanelCommand::Fail(arguments) => control::run_shortcut("fail", arguments, client).await,
        PanelCommand::Cancel(arguments) => control::run_shortcut("cancel", arguments, client).await,
        PanelCommand::Pause(arguments) => control::run_shortcut("pause", arguments, client).await,
        PanelCommand::Resume(arguments) => control::run_shortcut("resume", arguments, client).await,
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
    let mut body = validation::validate_file(&args.file)?;
    if body.get("sessionId").is_none() {
        let session_id = crate::session::read_session_id().ok_or("sessionId is missing; run `hiboss hook session-start` or add sessionId to the publication")?;
        body["sessionId"] = Value::String(session_id);
    }
    let key = args.idempotency_key.clone().unwrap_or_else(|| stable_key(&body, args.run_id.as_deref()));
    let response = client.publish_panel(&body, &key).await?;
    let panel = client.get_panel(&response.panel_id).await?;
    if panel.get("lifecycle").and_then(|value| value.get("taskState")).and_then(Value::as_str).is_some_and(|state| ["completed", "failed", "cancelled"].contains(&state)) {
        let run_id = args.run_id.as_deref().unwrap_or("<run-id>");
        return Err(format!("publication returned ended panel {}; use a new --run-id (current: {run_id})", response.panel_id).into());
    }
    println!("{}", serde_json::to_string(&publish_output(&response))?);
    Ok(())
}

async fn run_doctor(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let session_id = crate::session::read_session_id().ok_or("No resolved session; run `hiboss hook session-start` and retry")?;
    let sessions = client.list_sessions().await?;
    if !sessions.sessions.iter().any(|session| session.id == session_id) { return Err(format!("session {session_id} is not visible; run `hiboss hook session-start` to refresh it").into()); }
    let boss = resolved_boss(&client.list_agent_bosses().await?)?;
    let panels = client.list_panels(None).await?;
    let items = panels.get("panels").and_then(Value::as_array).or_else(|| panels.as_array());
    let Some(items) = items else { return Err("panel list response has no panels".into()); };
    let Some(panel) = items.iter().find(|panel| panel.get("sessionId").and_then(Value::as_str) == Some(session_id.as_str())).or_else(|| items.first()) else {
        println!("auth: ok\nprotocol: v2\nsession: {session_id}\nboss: {boss}\nrelay: not checked (no panel yet)");
        return Ok(());
    };
    let panel_id = panel.get("panelId").and_then(Value::as_str).ok_or("panel list returned no panelId")?;
    let details = client.get_panel(panel_id).await?;
    if details.get("targetBossId").and_then(Value::as_str) != Some(boss.as_str()) { return Err("panel target does not match the agent's single resolved boss".into()); }
    if details.get("definition").and_then(|definition| definition.get("protocolVersion")).and_then(Value::as_u64) != Some(2) { return Err("server does not support panel protocol v2; upgrade the server and CLI together".into()); }
    transport::subscribe(client, panel_id).await?;
    println!("auth: ok\nprotocol: v2\nsession: {session_id}\nboss: {boss}\nrelay: ticket and subscribe ok");
    Ok(())
}

fn resolved_boss(value: &Value) -> Result<String, Box<dyn Error>> {
    let bosses = value.get("bosses").and_then(Value::as_array).ok_or("boss API response has no bosses")?;
    match bosses.as_slice() {
        [boss] => boss.get("id").and_then(Value::as_str).map(str::to_owned).ok_or_else(|| "boss API response has no boss id".into()),
        [] => Err("No boss is resolved for this agent; grant access to one boss and retry".into()),
        _ => Err("Multiple bosses are resolved for this agent; set targetBossId explicitly and retry".into()),
    }
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
fn stable_key(value: &Value, run_id: Option<&str>) -> String { let input = json!({"document":value,"sessionId":value.get("sessionId"),"runId":run_id}); let bytes = serde_json::to_vec(&input).unwrap_or_default(); let hash = digest(&SHA256, &bytes); let hex = hash.as_ref().iter().map(|byte| format!("{byte:02x}")).collect::<String>(); format!("hiboss-panel-{hex}") }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_key_is_repeatable_for_same_document() { let value = json!({"title":"panel"}); assert_eq!(stable_key(&value, None), stable_key(&value, None)); }

    #[test]
    fn publish_output_contains_only_resume_ids() { let response = PanelPublishResponse { panel_id: "panel_1".into(), definition_revision: 3, extra: Default::default() }; assert_eq!(publish_output(&response), json!({"panelId":"panel_1","definitionRevision":3})); }

    #[test]
    fn field_uses_first_available_alias() { assert_eq!(field(&json!({"id":"panel_1"}), &["panelId", "id"]), "panel_1"); }

    #[test]
    fn resolves_only_one_accessible_boss() {
        assert_eq!(resolved_boss(&json!({"bosses":[{"id":"boss_1"}]})).expect("boss"), "boss_1");
        assert!(resolved_boss(&json!({"bosses":[]})).is_err());
        assert!(resolved_boss(&json!({"bosses":[{"id":"a"},{"id":"b"}]})).is_err());
    }
}
