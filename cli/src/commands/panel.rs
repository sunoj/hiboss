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
    validate_file_with_session(&args.file)?;
    println!("valid");
    Ok(())
}

async fn run_publish(args: &PanelPublishArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let body = validate_file_with_session(&args.file)?;
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
    let boss_ids = resolved_bosses(&client.list_agent_bosses().await?)?;
    let boss_status = format_boss_status(&boss_ids);
    let panels = client.list_panels(None).await?;
    let items = panels.get("panels").and_then(Value::as_array).or_else(|| panels.as_array());
    let Some(items) = items else { return Err("panel list response has no panels".into()); };
    let Some(panel) = items.iter().find(|panel| panel.get("sessionId").and_then(Value::as_str) == Some(session_id.as_str())).or_else(|| items.first()) else {
        println!("auth: ok\nprotocol: v2\nsession: {session_id}\n{boss_status}\nrelay: not checked (no panel yet)");
        return Ok(());
    };
    let panel_id = panel.get("panelId").and_then(Value::as_str).ok_or("panel list returned no panelId")?;
    let details = client.get_panel(panel_id).await?;
    if !panel_matches_bosses(details.get("targetBossId").and_then(Value::as_str), &boss_ids) { return Err("panel target does not match any resolved agent boss".into()); }
    let ticket = client.issue_panel_connection_ticket(panel_id).await?;
    if !supports_lease_release(&ticket.operations) { return Err("server relay does not support lease.release; deploy the worker before installing this CLI".into()); }
    transport::subscribe(client, panel_id, &ticket).await?;
    println!("auth: ok\nprotocol: v2 (lease.release)\nsession: {session_id}\n{boss_status}\nrelay: ticket and subscribe ok");
    Ok(())
}

fn supports_lease_release(operations: &[String]) -> bool { operations.iter().any(|operation| operation == "lease.release") }

fn validate_file_with_session(path: &std::path::Path) -> Result<Value, Box<dyn Error>> {
    let session_id = crate::session::read_session_id();
    validate_file_with_session_id(path, session_id.as_deref())
}

fn validate_file_with_session_id(path: &std::path::Path, session_id: Option<&str>) -> Result<Value, Box<dyn Error>> {
    let mut body = validation::read_file(path)?;
    if body.get("sessionId").is_none() {
        let session_id = session_id.ok_or("sessionId is missing; run `hiboss hook session-start` or add sessionId to the publication")?;
        body["sessionId"] = Value::String(session_id.to_owned());
    }
    validation::validate_publication(&body).map_err(|error| Box::new(error) as Box<dyn Error>)?;
    Ok(body)
}

fn resolved_bosses(value: &Value) -> Result<Vec<String>, Box<dyn Error>> {
    let bosses = value.get("bosses").and_then(Value::as_array).ok_or("boss API response has no bosses")?;
    if bosses.is_empty() {
        return Err("No boss is resolved for this agent; grant access to one boss and retry".into());
    }
    bosses.iter().map(|boss| boss.get("id").and_then(Value::as_str).map(str::to_owned).ok_or_else(|| "boss API response has no boss id".into())).collect()
}

fn format_boss_status(bosses: &[String]) -> String {
    match bosses {
        [boss] => format!("boss: {boss}"),
        _ => format!("boss: {} resolved (publication needs an explicit targetBossId)\nbosses: {}", bosses.len(), bosses.join(", ")),
    }
}

fn panel_matches_bosses(target_boss_id: Option<&str>, bosses: &[String]) -> bool {
    target_boss_id.is_some_and(|target| bosses.iter().any(|boss| boss == target))
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
    fn formats_one_several_and_no_resolved_bosses() {
        assert_eq!(resolved_bosses(&json!({"bosses":[{"id":"boss_1"}]})).expect("bosses"), vec!["boss_1"]);
        assert_eq!(format_boss_status(&["boss_1".into()]), "boss: boss_1");
        let bosses = resolved_bosses(&json!({"bosses":[{"id":"a"},{"id":"b"}]})).expect("bosses");
        assert_eq!(format_boss_status(&bosses), "boss: 2 resolved (publication needs an explicit targetBossId)\nbosses: a, b");
        assert!(resolved_bosses(&json!({"bosses":[]})).is_err());
    }

    #[test]
    fn panel_target_matches_any_resolved_boss() {
        let bosses = vec!["boss_a".into(), "boss_b".into()];
        assert!(panel_matches_bosses(Some("boss_b"), &bosses));
        assert!(!panel_matches_bosses(Some("boss_c"), &bosses));
    }

    #[test]
    fn sessionless_document_uses_session_before_validation() {
        let document = json!({
            "protocolVersion": 2,
            "targetBossId": "boss_1",
            "taskKey": "task_1",
            "title": "Panel",
            "catalogId": "hiboss.panel",
            "catalogVersion": 1,
            "spec": {"root": "main", "elements": {"main": {"type": "Metric", "props": {"label": "Done", "value": {"$state": "/task/done"}}, "children": []}}},
            "stateSchema": {"type": "object", "properties": {"task": {"type": "object", "properties": {"done": {"type": "integer"}}, "required": ["done"], "additionalProperties": false}}, "required": ["task"], "additionalProperties": false},
            "initialState": {"task": {"done": 0}}
        });
        let path = std::env::temp_dir().join(format!("hiboss-panel-session-test-{}.json", std::process::id()));
        std::fs::write(&path, serde_json::to_vec(&document).expect("document JSON")).expect("write document");
        let validated = validate_file_with_session_id(&path, Some("session_1")).expect("session autofill");
        assert_eq!(validated.get("sessionId").and_then(Value::as_str), Some("session_1"));
        let validate_error = validate_file_with_session_id(&path, None).expect_err("validate should require a session");
        let publish_error = validate_file_with_session_id(&path, None).expect_err("publish should require a session");
        assert_eq!(validate_error.to_string(), publish_error.to_string());
        assert!(validate_error.to_string().contains("hiboss hook session-start"));
        std::fs::remove_file(path).expect("remove document");
    }

    #[test]
    fn checks_for_lease_release_capability() {
        assert!(supports_lease_release(&["subscribe".into(), "lease.release".into()]));
        assert!(!supports_lease_release(&["subscribe".into()]));
    }
}
