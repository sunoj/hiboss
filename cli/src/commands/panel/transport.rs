// Purpose: Share authenticated v2 relay transport and task patch operations.
// Exports: Connection, relay frames, connect/release, subscribe, merge, and diff helpers.
// Dependencies: HiBossClient, relay errors, tokio-tungstenite, and serde_json.

use crate::client::{HiBossClient, PanelConnectionTicket};
use super::relay_helpers::relay_error;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::error::Error;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::{connect_async, tungstenite::{client::IntoClientRequest, Message}};

type Socket = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
pub(crate) type Writer = futures_util::stream::SplitSink<Socket, Message>;
pub(crate) type Reader = futures_util::stream::SplitStream<Socket>;
pub(crate) const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RelayFrame {
    pub(crate) kind: String,
    pub(crate) code: Option<String>,
    pub(crate) sequence: Option<u64>,
    #[serde(rename = "acceptedSequence")]
    pub(crate) accepted_sequence: Option<u64>,
    pub(crate) task: Option<Value>,
    pub(crate) epoch: Option<String>,
    pub(crate) snapshot: Option<Snapshot>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct Snapshot {
    pub(crate) sequence: u64,
    pub(crate) task: Value,
}

pub(crate) struct Connection {
    pub(crate) writer: Writer,
    pub(crate) reader: Reader,
    pub(crate) epoch: String,
}

#[derive(Debug)]
pub(crate) struct RelayFailure {
    pub(crate) code: String,
}

impl std::fmt::Display for RelayFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}", relay_error(Some(&self.code)))
    }
}

impl Error for RelayFailure {}

pub(crate) async fn connect(
    client: &HiBossClient,
    panel_id: &str,
    revision: u64,
    takeover: Option<&str>,
) -> Result<(Connection, Snapshot), Box<dyn Error>> {
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
            return Ok((Connection { writer, reader, epoch: frame.epoch.ok_or("lease ack has no server epoch")? }, frame.snapshot.ok_or("lease ack has no baseline")?));
        }
        if frame.kind == "error" { return Err(Box::new(RelayFailure { code: frame.code.unwrap_or_else(|| "unknown_error".to_owned()) })); }
    }
}

pub(crate) async fn subscribe(client: &HiBossClient, panel_id: &str, ticket: &PanelConnectionTicket) -> Result<(), Box<dyn Error>> {
    let mut request = client.panel_relay_url().into_client_request()?;
    request.headers_mut().insert("X-Panel-Connection-Ticket", ticket.ticket.parse()?);
    let (socket, _) = connect_async(request).await?;
    let (mut writer, mut reader) = socket.split();
    writer.send(Message::Text(json!({"protocolVersion":2,"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
    loop {
        let frame = receive_frame(&mut reader, "doctor subscribe").await?;
        if frame.kind == "state.snapshot" { return Ok(()); }
        if frame.kind == "error" { return Err(Box::new(RelayFailure { code: frame.code.unwrap_or_else(|| "unknown_error".to_owned()) })); }
    }
}

pub(crate) async fn release(connection: &mut Connection, panel_id: &str, revision: u64) -> Result<(), Box<dyn Error>> {
    let frame = json!({"protocolVersion":2,"kind":"lease.release","panelId":panel_id,"definitionRevision":revision,"epoch":connection.epoch});
    connection.writer.send(Message::Text(frame.to_string().into())).await?;
    loop {
        let frame = receive_frame(&mut connection.reader, "lease release").await?;
        if frame.kind == "lease.release.ack" { return Ok(()); }
        if frame.kind == "error" {
            let code = frame.code.as_deref().unwrap_or("unknown_error");
            return Err(release_error(Some(code)).into());
        }
    }
}

pub(crate) fn release_error(code: Option<&str>) -> String {
    match code {
        Some("invalid_command") | Some("unsupported_protocol") => "panel relay version mismatch: server does not support lease.release; upgrade the server and CLI together".into(),
        Some(code) => relay_error(Some(code)),
        None => relay_error(None),
    }
}

pub(crate) async fn receive_frame(reader: &mut Reader, stage: &str) -> Result<RelayFrame, Box<dyn Error>> {
    let message = timeout(HANDSHAKE_TIMEOUT, reader.next()).await?.ok_or_else(|| format!("relay closed during {stage}"))??;
    parse_frame(message)
}

pub(crate) fn parse_frame(message: Message) -> Result<RelayFrame, Box<dyn Error>> {
    let Message::Text(text) = message else { return Err("relay sent a non-text message".into()); };
    Ok(serde_json::from_str(text.as_ref())?)
}

pub(crate) fn snapshot_from(frame: RelayFrame) -> Result<Snapshot, Box<dyn Error>> {
    Ok(Snapshot { sequence: frame.sequence.unwrap_or(0), task: frame.task.ok_or("snapshot has no task")? })
}

pub(crate) fn merge_object(target: &mut Map<String, Value>, partial: &Map<String, Value>) {
    for (key, value) in partial {
        if let (Some(Value::Object(existing)), Value::Object(incoming)) = (target.get_mut(key), value) { merge_object(existing, incoming); }
        else { target.insert(key.clone(), value.clone()); }
    }
}

pub(crate) fn diff_values(old: &Value, new: &Value, path: &str) -> Vec<Value> {
    let (Some(old), Some(new)) = (old.as_object(), new.as_object()) else { return vec![json!({"op":"replace","path":path,"value":new})]; };
    let mut ops = Vec::new();
    for (key, value) in new {
        let child = format!("{path}/{}", escape_pointer(key));
        match old.get(key) { Some(previous) if same_value(previous, value) => {}, Some(previous) => ops.extend(diff_values(previous, value, &child)), None => ops.push(json!({"op":"add","path":child,"value":value})) }
    }
    ops
}

pub(crate) fn same_value(old: &Value, new: &Value) -> bool {
    match (old, new) {
        (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
        (Value::Array(a), Value::Array(b)) => a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same_value(a, b)),
        (Value::Object(a), Value::Object(b)) => a.len() == b.len() && a.iter().all(|(key, a)| b.get(key).is_some_and(|b| same_value(a, b))),
        _ => old == new,
    }
}

fn escape_pointer(value: &str) -> String { value.replace('~', "~0").replace('/', "~1") }

pub(crate) fn new_id() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |duration| duration.as_nanos());
    format!("hiboss-relay-{}-{nanos}", std::process::id())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compares_numeric_json_values_tolerantly() { assert!(same_value(&json!(1), &json!(1.0))); }

    #[test]
    fn diffs_nested_values_with_escaped_pointers() {
        let diff = diff_values(&json!({"a/b": 1}), &json!({"a/b": 2}), "/task");
        assert_eq!(diff[0]["path"], "/task/a~1b");
    }
}
