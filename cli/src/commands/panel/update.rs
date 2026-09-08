// Purpose: Publish one merged task observation through the v2 relay.
// Exports: PanelUpdateArgs and run.
// Dependencies: HiBossClient, session epochs, WebSocket relay, and serde_json.

use crate::{client::HiBossClient, session};
use clap::Args;
use futures_util::SinkExt;
use serde_json::{json, Value};
use std::error::Error;
use std::path::PathBuf;
use tokio::io::AsyncReadExt;
use tokio_tungstenite::tungstenite::Message;

use super::relay_helpers::live_epoch;
use super::transport::{connect, diff_values, merge_object, new_id, receive_frame, release, Connection, RelayFailure, Snapshot};
#[cfg(test)]
use super::transport::release_error;

#[derive(Debug, Args)]
pub struct PanelUpdateArgs {
    pub panel_id: String,
    #[arg(value_name = "JSON", conflicts_with = "file")]
    pub json: Option<String>,
    #[arg(long, value_name = "FILE", conflicts_with = "json")]
    pub file: Option<PathBuf>,
    #[arg(long, help = "Explicitly replace this currently active producer epoch")]
    pub takeover_epoch: Option<String>,
}

pub async fn run(args: &PanelUpdateArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let panel = client.get_panel(&args.panel_id).await?;
    let revision = panel.get("definitionRevision").and_then(Value::as_u64).unwrap_or(1);
    let partial = read_partial(args).await?;
    let (mut connection, snapshot) = connect_with_recovery(client, &args.panel_id, revision, args.takeover_epoch.as_deref()).await?;
    session::write_panel_epoch(&args.panel_id, Some(&connection.epoch))?;
    let desired = merge_task(snapshot.task.clone(), partial)?;
    let ops = diff_values(&snapshot.task, &desired, "/task");
    let kind = if ops.is_empty() { "state.unchanged" } else { "state.update" };
    connection.writer.send(Message::Text(json!({"protocolVersion":2,"kind":kind,"panelId":args.panel_id,"definitionRevision":revision,"epoch":connection.epoch,"updateId":new_id(),"baseSequence":snapshot.sequence,"ops":ops}).to_string().into())).await?;
    let sequence = receive_ack(&mut connection).await?;
    release(&mut connection, &args.panel_id, revision).await?;
    session::write_panel_epoch(&args.panel_id, None)?;
    println!("{sequence}");
    Ok(())
}

async fn read_partial(args: &PanelUpdateArgs) -> Result<Value, Box<dyn Error>> {
    let body = match (&args.json, &args.file) {
        (Some(value), None) => value.clone(),
        (None, Some(path)) => std::fs::read_to_string(path)?,
        (None, None) => { let mut input = String::new(); tokio::io::stdin().read_to_string(&mut input).await?; input }
        (Some(_), Some(_)) => return Err("update accepts JSON or --file, not both".into()),
    };
    let value: Value = serde_json::from_str(&body)?;
    if !value.is_object() { return Err("update JSON must be a task object".into()); }
    Ok(value)
}

fn merge_task(mut task: Value, partial: Value) -> Result<Value, Box<dyn Error>> {
    let target = task.as_object_mut().ok_or("panel task must be an object")?;
    let partial = partial.as_object().ok_or("update JSON must be an object")?;
    merge_object(target, partial);
    Ok(task)
}

async fn connect_with_recovery(client: &HiBossClient, panel_id: &str, revision: u64, takeover: Option<&str>) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    match connect(client, panel_id, revision, takeover).await {
        Ok(value) => Ok(value),
        Err(error) if error.downcast_ref::<RelayFailure>().is_some_and(|failure| failure.code == "lease_conflict") => {
            let state = client.panel_state(panel_id).await?;
            let recorded = session::read_panel_epoch(panel_id);
            let live = live_epoch(&state);
            if live.is_some() && live == recorded { return connect(client, panel_id, revision, live.as_deref()).await; }
            let exact = live.map_or_else(|| "<live-epoch>".to_owned(), |epoch| epoch);
            Err(format!("panel lease_conflict: live epoch is {exact}; retry with `hiboss panel update {panel_id} --takeover-epoch {exact}`").into())
        }
        Err(error) => Err(error),
    }
}

async fn receive_ack(connection: &mut Connection) -> Result<u64, Box<dyn Error>> {
    loop {
        let frame = receive_frame(&mut connection.reader, "update").await?;
        if frame.kind == "state.ack" { return frame.sequence.ok_or_else(|| "state ack has no sequence".into()); }
        if frame.kind == "error" { return Err(Box::new(RelayFailure { code: frame.code.unwrap_or_else(|| "unknown_error".into()) })); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merges_nested_partial_task_values() { assert_eq!(merge_task(json!({"a":{"b":1},"c":2}), json!({"a":{"d":3}})).expect("merge"), json!({"a":{"b":1,"d":3},"c":2})); }

    #[test]
    fn unchanged_task_has_no_patch_operations() { assert!(diff_values(&json!({"a":1}), &json!({"a":1}), "/task").is_empty()); }

    #[test]
    fn release_compatibility_is_a_version_mismatch() { assert!(release_error(Some("invalid_command")).contains("version mismatch")); }
}
