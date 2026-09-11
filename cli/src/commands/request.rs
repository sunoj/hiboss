// Purpose: Publish, inspect, revise, withdraw, and wait for durable questionnaires.
// Exports: RequestArgs and run; answers stay structured JSON and timeouts stay pending.
// Dependencies: clap, HiBossClient, serde_json, and tokio timers.

use crate::client::HiBossClient;
use clap::{Args, Subcommand};
use reqwest::Method;
use serde_json::{json, Value};
use std::{error::Error, path::PathBuf, time::Duration};

#[derive(Debug, Args)]
pub struct RequestArgs {
    #[command(subcommand)]
    pub command: RequestCommand,
}

#[derive(Debug, Subcommand)]
pub enum RequestCommand {
    #[command(about = "Publish an intake questionnaire attached to a panel")]
    Publish { panel_id: String, file: PathBuf, #[arg(long)] idempotency_key: String },
    #[command(about = "List a panel's questionnaires and needsInput status")]
    List { panel_id: String },
    #[command(about = "Read a questionnaire, its pinned definition, and accepted answer")]
    Show { id: String, #[arg(long)] revision: Option<u64> },
    #[command(about = "Replace an open questionnaire with an explicit revision check")]
    Replace { id: String, file: PathBuf, #[arg(long)] expected_revision: u64 },
    #[command(about = "Withdraw an open questionnaire without creating an answer")]
    Withdraw { id: String, #[arg(long)] expected_revision: u64, #[arg(long)] reason: String },
    #[command(about = "Wait for a durable structured answer; a timeout never selects defaults")]
    Wait { id: String, #[arg(long, default_value_t = 1800)] timeout: u64 },
    #[command(about = "Acknowledge receipt of an answer; does not claim execution")]
    Ack { id: String, submission_id: String },
}

pub async fn run(args: &RequestArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let output = match &args.command {
        RequestCommand::Publish { panel_id, file, idempotency_key } => {
            client.questionnaire_http(Method::POST, &format!("panels/{panel_id}/requests"), Some(read_file(file)?), Some(idempotency_key)).await?
        }
        RequestCommand::List { panel_id } => client.questionnaire_http(Method::GET, &format!("panels/{panel_id}/requests"), None, None).await?,
        RequestCommand::Show { id, revision } => {
            let suffix = revision.map(|value| format!("?revision={value}")).unwrap_or_default();
            client.questionnaire_http(Method::GET, &format!("interaction-requests/{id}{suffix}"), None, None).await?
        }
        RequestCommand::Replace { id, file, expected_revision } => {
            let mut body = read_file(file)?;
            body["expectedRevision"] = json!(expected_revision);
            client.questionnaire_http(Method::PUT, &format!("interaction-requests/{id}"), Some(body), None).await?
        }
        RequestCommand::Withdraw { id, expected_revision, reason } => {
            client.questionnaire_http(Method::POST, &format!("interaction-requests/{id}/withdraw"), Some(json!({"expectedRevision":expected_revision,"reason":reason})), None).await?
        }
        RequestCommand::Ack { id, submission_id } => client.questionnaire_http(Method::POST, &format!("interaction-requests/{id}/submissions/{submission_id}/ack"), None, None).await?,
        RequestCommand::Wait { id, timeout } => wait(client, id, *timeout).await?,
    };
    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

fn read_file(path: &PathBuf) -> Result<Value, Box<dyn Error>> {
    let value: Value = serde_json::from_slice(&std::fs::read(path)?)?;
    if !value.is_object() { return Err("questionnaire file must contain a JSON object".into()); }
    Ok(value)
}

async fn wait(client: &HiBossClient, id: &str, timeout: u64) -> Result<Value, Box<dyn Error>> {
    let started = std::time::Instant::now();
    loop {
        let value = client.questionnaire_http(Method::GET, &format!("interaction-requests/{id}"), None, None).await?;
        match value.get("state").and_then(Value::as_str) {
            Some("accepted") => return Ok(value.get("submission").cloned().ok_or("accepted request has no submission")?),
            Some("withdrawn" | "expired") => return Ok(value),
            Some("open") => {},
            _ => return Err("invalid questionnaire state".into()),
        }
        let remaining = Duration::from_secs(timeout).saturating_sub(started.elapsed());
        if remaining.is_zero() { return Ok(json!({"requestId":id,"state":"open","timedOut":true})); }
        tokio::time::sleep(remaining.min(Duration::from_secs(2))).await;
    }
}
