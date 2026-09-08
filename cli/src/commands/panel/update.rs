// Purpose: Publish one merged task observation through the v2 relay.
// Exports: PanelUpdateArgs, run, and doctor relay checks.
// Dependencies: HiBossClient, session epochs, WebSocket relay, and serde_json.

use crate::{client::HiBossClient, session};
use clap::Args;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Map, Value};
use std::error::Error;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::{client::IntoClientRequest, Message}};

use super::relay_helpers::relay_error;

const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);

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

#[derive(Debug, Default, serde::Deserialize)]
struct RelayFrame {
    kind: String,
    code: Option<String>,
    sequence: Option<u64>,
    epoch: Option<String>,
    snapshot: Option<Snapshot>,
}

#[derive(Debug, serde::Deserialize)]
struct Snapshot { sequence: u64, task: Value }

struct Connection {
    writer: futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>, Message>,
    reader: futures_util::stream::SplitStream<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>>,
    epoch: String,
}

#[derive(Debug)]
struct RelayFailure { code: String }
impl std::fmt::Display for RelayFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(formatter, "{}", relay_error(Some(&self.code))) }
}
impl Error for RelayFailure {}

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

fn merge_object(target: &mut Map<String, Value>, partial: &Map<String, Value>) {
    for (key, value) in partial {
        if let (Some(Value::Object(existing)), Value::Object(incoming)) = (target.get_mut(key), value) { merge_object(existing, incoming); }
        else { target.insert(key.clone(), value.clone()); }
    }
}

fn diff_values(old: &Value, new: &Value, path: &str) -> Vec<Value> {
    let (Some(old), Some(new)) = (old.as_object(), new.as_object()) else { return vec![json!({"op":"replace","path":path,"value":new})]; };
    let mut ops = Vec::new();
    for (key, value) in new {
        let child = format!("{path}/{}", key.replace('~', "~0").replace('/', "~1"));
        match old.get(key) { Some(previous) if previous == value => {}, Some(previous) => ops.extend(diff_values(previous, value, &child)), None => ops.push(json!({"op":"add","path":child,"value":value})) }
    }
    ops
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

async fn connect(client: &HiBossClient, panel_id: &str, revision: u64, takeover: Option<&str>) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    let ticket = client.issue_panel_connection_ticket(panel_id).await?;
    let mut request = client.panel_relay_url().into_client_request()?;
    request.headers_mut().insert("X-Panel-Connection-Ticket", ticket.ticket.parse()?);
    let (socket, _) = connect_async(request).await?;
    let (mut writer, mut reader) = socket.split();
    writer.send(Message::Text(json!({"protocolVersion":2,"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
    let mut claim = json!({"protocolVersion":2,"kind":"lease.claim","panelId":panel_id,"definitionRevision":revision,"requestId":new_id()});
    if let Some(epoch) = takeover { claim["takeoverEpoch"] = json!(epoch); }
    writer.send(Message::Text(claim.to_string().into())).await?;
    loop {
        let frame = receive_frame(&mut reader, "handshake").await?;
        if frame.kind == "lease.ack" {
            return Ok((Connection { writer, reader, epoch: frame.epoch.ok_or("lease ack has no epoch")? }, frame.snapshot.ok_or("lease ack has no snapshot")?));
        }
        if frame.kind == "error" { return Err(Box::new(RelayFailure { code: frame.code.unwrap_or_else(|| "unknown_error".into()) })); }
    }
}

async fn receive_ack(connection: &mut Connection) -> Result<u64, Box<dyn Error>> {
    loop {
        let frame = receive_frame(&mut connection.reader, "update").await?;
        if frame.kind == "state.ack" { return frame.sequence.ok_or_else(|| "state ack has no sequence".into()); }
        if frame.kind == "error" { return Err(Box::new(RelayFailure { code: frame.code.unwrap_or_else(|| "unknown_error".into()) })); }
    }
}

async fn release(connection: &mut Connection, panel_id: &str, revision: u64) -> Result<(), Box<dyn Error>> {
    connection.writer.send(Message::Text(json!({"protocolVersion":2,"kind":"lease.release","panelId":panel_id,"definitionRevision":revision,"epoch":connection.epoch}).to_string().into())).await?;
    loop {
        let frame = receive_frame(&mut connection.reader, "lease release").await?;
        if frame.kind == "lease.release.ack" { return Ok(()); }
        if frame.kind == "error" { return Err(release_error(frame.code.as_deref()).into()); }
    }
}

async fn receive_frame(reader: &mut futures_util::stream::SplitStream<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>>, stage: &str) -> Result<RelayFrame, Box<dyn Error>> {
    let message = timeout(HANDSHAKE_TIMEOUT, reader.next()).await?.ok_or_else(|| format!("relay closed during {stage}"))??;
    let Message::Text(text) = message else { return Err("relay sent a non-text message".into()); };
    Ok(serde_json::from_str(text.as_ref())?)
}

fn release_error(code: Option<&str>) -> String {
    match code {
        Some("invalid_command") | Some("unsupported_protocol") => "panel relay version mismatch: server does not support lease.release; upgrade the server and CLI together".into(),
        Some(code) => format!("panel relay stopped: {code}; read `hiboss panel state <id>` before retrying"),
        None => "panel relay stopped: unknown error".into(),
    }
}

pub async fn doctor(client: &HiBossClient, panel_id: &str) -> Result<(), Box<dyn Error>> {
    let ticket = client.issue_panel_connection_ticket(panel_id).await?;
    let mut request = client.panel_relay_url().into_client_request()?;
    request.headers_mut().insert("X-Panel-Connection-Ticket", ticket.ticket.parse()?);
    let (socket, _) = connect_async(request).await?;
    let (mut writer, mut reader) = socket.split();
    writer.send(Message::Text(json!({"protocolVersion":2,"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
    loop {
        let frame = receive_frame(&mut reader, "doctor subscribe").await?;
        if frame.kind == "state.snapshot" { return Ok(()); }
        if frame.kind == "error" { return Err(format!("panel doctor relay subscribe failed: {}", frame.code.unwrap_or_else(|| "unknown_error".into())).into()); }
    }
}

fn live_epoch(state: &Value) -> Option<String> {
    let expires = state.get("leaseExpiresAt").and_then(Value::as_str)?;
    let expires_at = time::OffsetDateTime::parse(expires, &time::format_description::well_known::Rfc3339).ok()?.unix_timestamp();
    (expires_at > time::OffsetDateTime::now_utc().unix_timestamp()).then(|| state.get("epoch").and_then(Value::as_str).map(str::to_owned)).flatten()
}

fn new_id() -> String { format!("hiboss-update-{}", uuid_like()) }
fn uuid_like() -> String { let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |duration| duration.as_nanos()); format!("{}-{now}", std::process::id()) }

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
