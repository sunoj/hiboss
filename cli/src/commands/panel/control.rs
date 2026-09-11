// Purpose: Build and execute version-safe lifecycle shortcut commands.
// Exports: PanelLifecycleArgs and run_shortcut.
// Dependencies: HiBossClient panel reads, session identity, and lifecycle HTTP calls.

use crate::client::HiBossClient;
use clap::Args;
use ring::digest::{digest, SHA256};
use serde_json::{json, Value};
use std::error::Error;

use super::relay_helpers::live_epoch;

#[derive(Debug, Args)]
pub struct PanelLifecycleArgs {
    pub id: String,
    #[arg(long)] pub title: Option<String>,
    #[arg(long)] pub message: Option<String>,
    #[arg(long)] pub code: Option<String>,
    #[arg(long, value_name = "JSON|@FILE")] pub final_task: Option<String>,
    #[arg(long, help = "Override the retry-safe default idempotency key")]
    pub idempotency_key: Option<String>,
    #[arg(long, value_name = "REASON", help = "Explicitly withdraw unanswered questionnaires when ending the task")]
    pub withdraw_requests: Option<String>,
}

#[derive(Debug, Args)]
pub struct PanelRenewArgs {
    pub id: String,
    #[arg(long, value_name = "SECONDS", help = "Replace the visibility window in seconds (60..604800)")]
    pub ttl: Option<u64>,
    #[arg(long, help = "Override the retry-safe default idempotency key")]
    pub idempotency_key: Option<String>,
}

pub async fn run_renew(args: &PanelRenewArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    if args.ttl.is_some_and(|ttl| !(60..=604800).contains(&ttl)) { return Err("--ttl must be an integer from 60 to 604800".into()); }
    let panel = client.get_panel(&args.id).await?;
    let metadata_version = panel.get("metadataVersion").and_then(Value::as_u64).ok_or("panel response has no metadataVersion")?;
    let definition_revision = panel.get("definitionRevision").and_then(Value::as_u64).ok_or("panel response has no definitionRevision")?;
    let session_id = panel.get("sessionId").and_then(Value::as_str).ok_or("panel response has no sessionId")?;
    let mut body = json!({"protocolVersion":2,"expectedMetadataVersion":metadata_version,"expectedDefinitionRevision":definition_revision});
    if let Some(ttl) = args.ttl { body["ttlSeconds"] = json!(ttl); }
    let key = args.idempotency_key.clone().unwrap_or_else(|| renew_key(&args.id, args.ttl, session_id, metadata_version));
    let result = client.panel_command(&args.id, "renew", &body, &key).await?;
    let expires_at = result.get("expiresAt").and_then(Value::as_str).ok_or("panel renewal response has no expiresAt")?;
    println!("Expires at: {expires_at}");
    Ok(())
}

pub async fn run_shortcut(action: &str, args: &PanelLifecycleArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let panel = client.get_panel(&args.id).await?;
    let state = client.panel_state(&args.id).await?;
    let metadata_version = panel.get("metadataVersion").and_then(Value::as_u64).ok_or("panel response has no metadataVersion")?;
    let definition_revision = panel.get("definitionRevision").and_then(Value::as_u64).ok_or("panel response has no definitionRevision")?;
    let session_id = panel.get("sessionId").and_then(Value::as_str).ok_or("panel response has no sessionId")?;
    if action == "fail" && args.code.is_none() { return Err("fail requires --code <CODE>".into()); }
    if action != "fail" && args.code.is_some() { return Err("--code is only valid for fail".into()); }
    let expected_epoch = live_epoch(&state);
    let mut body = json!({"protocolVersion":2,"action":action,"expectedMetadataVersion":metadata_version,"expectedDefinitionRevision":definition_revision,"expectedEpoch":expected_epoch,"expectedState":{"epoch":state.get("epoch").cloned().unwrap_or(Value::Null),"sequence":state.get("sequence").and_then(Value::as_u64).ok_or("panel state has no sequence")?},"openRequests":"reject"});
    if let Some(final_task) = &args.final_task { body["finalTask"] = parse_json_or_file(final_task)?; }
    if let Some(reason) = &args.withdraw_requests {
        if !matches!(action, "complete" | "fail" | "cancel") || reason.trim().is_empty() { return Err("--withdraw-requests needs a reason and a terminal command".into()); }
        body["openRequests"] = json!("withdraw");
        body["withdrawalReason"] = json!(reason);
    }
    if matches!(action, "complete" | "fail" | "cancel") {
        let title = args.title.clone().unwrap_or_else(|| default_title(action));
        let mut result = json!({"title":title});
        if let Some(message) = &args.message { result["message"] = json!(message); }
        if let Some(code) = &args.code { result["code"] = json!(code); }
        body["result"] = result;
    } else if args.title.is_some() || args.message.is_some() || args.code.is_some() || args.final_task.is_some() {
        return Err(format!("{action} does not accept result or final-task options").into());
    }
    let key = args.idempotency_key.clone().unwrap_or_else(|| shortcut_key(&args.id, action, session_id, metadata_version));
    let result = client.panel_command(&args.id, "lifecycle", &body, &key).await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    if result.get("status").and_then(Value::as_str) == Some("pending") { return Err("result is still saving; retry the same command with the same idempotency key".into()); }
    Ok(())
}

fn parse_json_or_file(value: &str) -> Result<Value, Box<dyn Error>> {
    let body = value.strip_prefix('@').map_or_else(|| Ok(value.to_owned()), std::fs::read_to_string)?;
    Ok(serde_json::from_str(&body)?)
}

fn default_title(action: &str) -> String { let mut chars = action.chars(); chars.next().map_or_else(|| action.to_owned(), |first| first.to_uppercase().collect::<String>() + chars.as_str()) }

fn shortcut_key(panel_id: &str, action: &str, session_id: &str, version: u64) -> String {
    let value = json!({"panelId":panel_id,"action":action,"sessionId":session_id,"expectedMetadataVersion":version});
    let hash = digest(&SHA256, serde_json::to_string(&value).unwrap_or_default().as_bytes());
    format!("hiboss-panel-{action}-{}", hash.as_ref().iter().map(|byte| format!("{byte:02x}")).collect::<String>())
}

fn renew_key(panel_id: &str, ttl: Option<u64>, session_id: &str, version: u64) -> String {
    let value = json!({"panelId":panel_id,"action":"renew","ttlSeconds":ttl,"sessionId":session_id,"expectedMetadataVersion":version});
    let hash = digest(&SHA256, serde_json::to_string(&value).unwrap_or_default().as_bytes());
    format!("hiboss-panel-renew-{}", hash.as_ref().iter().map(|byte| format!("{byte:02x}")).collect::<String>())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shortcut_key_includes_panel_action_session_and_version() {
        assert_ne!(shortcut_key("p", "complete", "s", 1), shortcut_key("p", "complete", "s", 2));
    }

    #[test]
    fn renew_key_includes_the_requested_ttl() {
        assert_ne!(renew_key("p", None, "s", 1), renew_key("p", Some(120), "s", 1));
    }

    #[test]
    fn parses_inline_final_task() { assert_eq!(parse_json_or_file(r#"{"done":2}"#).expect("task"), json!({"done":2})); }

    #[test]
    fn title_defaults_to_action_name() { assert_eq!(default_title("cancel"), "Cancel"); }
}
