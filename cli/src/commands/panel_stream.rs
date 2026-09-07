// Purpose: Produce live panel state from NDJSON through the authenticated relay.
// Exports: PanelStreamArgs and run.
// Dependencies: clap, futures-util, tokio-tungstenite, serde_json, and HiBossClient.

use crate::client::HiBossClient;
use clap::Args;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::error::Error;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::io::{self, AsyncBufReadExt};
use tokio::sync::mpsc;
use tokio::time::{sleep, sleep_until, timeout};
use tokio_tungstenite::{connect_async, tungstenite::{client::IntoClientRequest, Message}};

const BATCH_WINDOW: Duration = Duration::from_millis(20);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
const ACK_DRAIN_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_RECONNECTS: usize = 5;
#[derive(Debug, Args)]
pub struct PanelStreamArgs {
    #[arg(value_name = "PANEL_ID")]
    pub panel_id: String,
}

#[derive(Debug, Default, Deserialize)]
struct RelayFrame {
    kind: String,
    code: Option<String>,
    sequence: Option<u64>,
    #[serde(rename = "acceptedSequence")]
    accepted_sequence: Option<u64>,
    task: Option<Value>,
}
#[derive(Debug)]
struct Snapshot { sequence: u64, task: Value }

struct Connection {
    writer: futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>, Message>,
    reader: futures_util::stream::SplitStream<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>>,
    epoch: String,
}
struct Batcher {
    pending: bool,
    deadline: Option<Instant>,
    window: Duration,
}
impl Batcher {
    fn new(window: Duration) -> Self { Self { pending: false, deadline: None, window } }
    fn push(&mut self, now: Instant) { self.pending = true; self.deadline.get_or_insert(now + self.window); }
    fn due(&self, now: Instant) -> bool { self.pending && self.deadline.is_some_and(|deadline| now >= deadline) }
    fn force(&mut self) { self.pending = true; self.deadline = Some(Instant::now()); }
    fn clear(&mut self) { self.pending = false; self.deadline = None; }
}

struct StreamState {
    acknowledged: Value,
    desired: Value,
    sequence: u64,
    in_flight: Option<Value>,
    ambiguous: bool,
    batch: Batcher,
}
impl StreamState {
    fn from_snapshot(snapshot: Snapshot) -> Result<Self, Box<dyn Error>> {
        if !snapshot.task.is_object() { return Err("panel snapshot task must be an object".into()); }
        Ok(Self { acknowledged: snapshot.task.clone(), desired: snapshot.task, sequence: snapshot.sequence, in_flight: None, ambiguous: false, batch: Batcher::new(BATCH_WINDOW) })
    }

    fn add_partial(&mut self, partial: Value) -> Result<(), Box<dyn Error>> {
        let partial = partial.as_object().ok_or("each stream line must be a JSON object")?;
        merge_object(self.desired.as_object_mut().ok_or("panel task must be an object")?, partial);
        self.batch.push(Instant::now());
        Ok(())
    }

    fn ready(&self, now: Instant) -> bool { self.in_flight.is_none() && self.batch.due(now) && self.desired != self.acknowledged }

    fn acknowledge(&mut self, sequence: u64) -> bool {
        let Some(target) = self.in_flight.take() else { return false; };
        self.acknowledged = target;
        self.sequence = sequence;
        true
    }

    fn resync(&mut self, snapshot: Snapshot) -> Result<(), Box<dyn Error>> {
        if !snapshot.task.is_object() { return Err("panel resync task must be an object".into()); }
        self.acknowledged = snapshot.task;
        self.sequence = snapshot.sequence;
        self.in_flight = None;
        if self.desired != self.acknowledged { self.batch.force(); }
        Ok(())
    }

    fn reconnect(&mut self, snapshot: Snapshot) -> Result<(), Box<dyn Error>> {
        if self.in_flight.is_some() { self.ambiguous = true; }
        self.resync(snapshot)
    }

    fn finished(&self) -> bool { self.in_flight.is_none() && !self.batch.pending && !self.ambiguous }
}

pub async fn run(args: &PanelStreamArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let panel = client.get_panel(&args.panel_id).await?;
    let revision = panel.get("definitionRevision").and_then(Value::as_u64).unwrap_or(1);
    let (mut connection, snapshot) = connect(client, &args.panel_id).await?;
    let mut state = StreamState::from_snapshot(snapshot)?;
    let (tx, mut rx) = mpsc::channel::<Result<String, String>>(32);
    tokio::spawn(read_stdin(tx));
    let mut input_closed = false;
    let mut drain_deadline = None;

    loop {
        if input_closed && state.ambiguous && state.in_flight.is_none() { return Err("stream ended with unacknowledged work".into()); }
        if input_closed && state.finished() { return Ok(()); }
        let deadline = state.batch.deadline;
        let wake_at = deadline.map_or_else(Instant::now, |value| value);
        let drain_at = drain_deadline.map_or_else(Instant::now, |value| value);
        tokio::select! {
            line = rx.recv(), if !input_closed => match line {
                Some(Ok(line)) => if !line.trim().is_empty() { state.add_partial(serde_json::from_str(&line)?)?; },
                Some(Err(error)) => return Err(error.into()),
                None => { input_closed = true; if state.in_flight.is_some() { drain_deadline = Some(Instant::now() + ACK_DRAIN_TIMEOUT); } },
            },
            frame = connection.reader.next() => match frame {
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {
                    let (next, snapshot) = reconnect(client, &args.panel_id).await?;
                    state.reconnect(snapshot)?;
                    connection = next;
                }
                Some(Ok(message)) => handle_message(&mut connection, &mut state, message, &args.panel_id).await?,
            },
            _ = sleep_until(tokio::time::Instant::from_std(wake_at)), if deadline.is_some() && state.in_flight.is_none() => {
                send_update(&mut connection.writer, &mut state, &args.panel_id, revision, &connection.epoch).await?;
            },
            _ = sleep_until(tokio::time::Instant::from_std(drain_at)), if drain_deadline.is_some() => return Err("stream ended with unacknowledged work".into()),
        }
        if state.in_flight.is_none() { drain_deadline = None; }
        if state.ready(Instant::now()) {
            send_update(&mut connection.writer, &mut state, &args.panel_id, revision, &connection.epoch).await?;
        }
        if input_closed && state.in_flight.is_some() && drain_deadline.is_none() { drain_deadline = Some(Instant::now() + ACK_DRAIN_TIMEOUT); }
    }
}
async fn read_stdin(tx: mpsc::Sender<Result<String, String>>) {
    let mut lines = io::BufReader::new(io::stdin()).lines();
    loop {
        match lines.next_line().await {
            Ok(Some(line)) => { if tx.send(Ok(line)).await.is_err() { return; } }
            Ok(None) => return,
            Err(error) => { let _ = tx.send(Err(error.to_string())).await; return; }
        }
    }
}

async fn connect(client: &HiBossClient, panel_id: &str) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    let ticket = client.issue_panel_connection_ticket(panel_id).await?;
    let mut request = client.panel_relay_url().into_client_request()?;
    request.headers_mut().insert("X-Panel-Connection-Ticket", ticket.ticket.parse()?);
    let (socket, _) = connect_async(request).await?;
    let epoch = new_epoch();
    let (mut writer, mut reader) = socket.split();
    writer.send(Message::Text(json!({"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
    writer.send(Message::Text(json!({"kind":"lease.claim","panelId":panel_id,"epoch":epoch}).to_string().into())).await?;
    let mut snapshot = None;
    let mut lease_ack = false;
    while snapshot.is_none() || !lease_ack {
        let message = timeout(HANDSHAKE_TIMEOUT, reader.next()).await?.ok_or("relay closed during handshake")??;
        let frame = parse_frame(message)?;
        match frame.kind.as_str() {
            "state.snapshot" => snapshot = Some(snapshot_from(frame)?),
            "lease.ack" => lease_ack = true,
            "error" => return Err(relay_error(frame.code.as_deref()).into()),
            _ => {}
        }
    }
    Ok((Connection { writer, reader, epoch }, snapshot.ok_or("relay sent no snapshot")?))
}

async fn reconnect(client: &HiBossClient, panel_id: &str) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    for attempt in 0..MAX_RECONNECTS {
        match connect(client, panel_id).await {
            Ok(value) => return Ok(value),
            Err(error) if attempt + 1 < MAX_RECONNECTS => { sleep(Duration::from_millis(100 * 2u64.pow(attempt as u32))).await; let _ = error; }
            Err(error) => return Err(format!("relay reconnect failed: {error}").into()),
        }
    }
    Err("relay reconnect failed".into())
}

async fn handle_message(connection: &mut Connection, state: &mut StreamState, message: Message, panel_id: &str) -> Result<(), Box<dyn Error>> {
    if let Message::Ping(payload) = message { connection.writer.send(Message::Pong(payload)).await?; return Ok(()); }
    let frame = parse_frame(message)?;
    match frame_action(&frame) {
        FrameAction::Acknowledge(sequence) => if state.acknowledge(sequence) { println!("ack {sequence}"); },
        FrameAction::Resync => {
            connection.writer.send(Message::Text(json!({"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
            let snapshot = receive_snapshot(&mut connection.reader).await?;
            state.resync(snapshot)?;
        }
        FrameAction::Stop(reason) => return Err(reason.into()),
        FrameAction::Ignore => {}
    }
    Ok(())
}

/// What a frame means, decided without touching the socket so the decision can be tested.
/// Keeping this separate is the point: a fenced producer that keeps fighting for the lease
/// makes two agents thrash and the panel flicker between them, and that is a property of
/// the decision rather than of the I/O around it.
#[derive(Debug, PartialEq, Eq)]
enum FrameAction {
    Acknowledge(u64),
    Resync,
    Stop(String),
    Ignore,
}

fn frame_action(frame: &RelayFrame) -> FrameAction {
    match frame.kind.as_str() {
        "state.ack" => frame
            .accepted_sequence
            .or(frame.sequence)
            .map_or(FrameAction::Ignore, FrameAction::Acknowledge),
        "resync" => FrameAction::Resync,
        "error" => match frame.code.as_deref() {
            Some("resync_required") => FrameAction::Resync,
            Some(code) => FrameAction::Stop(relay_error(Some(code))),
            None => FrameAction::Stop("relay returned an unspecified error".to_owned()),
        },
        _ => FrameAction::Ignore,
    }
}

async fn receive_snapshot(reader: &mut futures_util::stream::SplitStream<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>>) -> Result<Snapshot, Box<dyn Error>> {
    loop {
        let message = timeout(HANDSHAKE_TIMEOUT, reader.next()).await?.ok_or("relay closed during resync")??;
        let frame = parse_frame(message)?;
        if frame.kind == "state.snapshot" { return snapshot_from(frame); }
        if frame.kind == "error" { return Err(relay_error(frame.code.as_deref()).into()); }
    }
}

async fn send_update(writer: &mut futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>, Message>, state: &mut StreamState, panel_id: &str, revision: u64, epoch: &str) -> Result<(), Box<dyn Error>> {
    let ops = diff_values(&state.acknowledged, &state.desired, "/task");
    if ops.is_empty() { state.batch.clear(); return Ok(()); }
    state.in_flight = Some(state.desired.clone());
    state.batch.clear();
    let update = json!({"protocolVersion":1,"kind":"state.update","panelId":panel_id,"definitionRevision":revision,"epoch":epoch,"updateId":new_epoch(),"baseSequence":state.sequence,"ops":ops});
    writer.send(Message::Text(serde_json::to_string(&update)?.into())).await?;
    Ok(())
}

fn parse_frame(message: Message) -> Result<RelayFrame, Box<dyn Error>> {
    let Message::Text(text) = message else { return Err("relay sent a non-text message".into()); };
    Ok(serde_json::from_str(text.as_ref())?)
}

fn snapshot_from(frame: RelayFrame) -> Result<Snapshot, Box<dyn Error>> {
    Ok(Snapshot { sequence: frame.sequence.unwrap_or(0), task: frame.task.ok_or("snapshot has no task")? })
}

fn relay_error(code: Option<&str>) -> String { format!("panel relay stopped: {}", code.unwrap_or("unknown error")) }

fn new_epoch() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |duration| duration.as_nanos());
    format!("hiboss-{}-{nanos}", std::process::id())
}

fn merge_object(target: &mut Map<String, Value>, partial: &Map<String, Value>) {
    for (key, value) in partial {
        if let (Some(Value::Object(existing)), Value::Object(incoming)) = (target.get_mut(key), value) { merge_object(existing, incoming); } else { target.insert(key.clone(), value.clone()); }
    }
}

fn diff_values(old: &Value, new: &Value, path: &str) -> Vec<Value> {
    let (Some(old), Some(new)) = (old.as_object(), new.as_object()) else { return vec![json!({"op":"replace","path":path,"value":new})]; };
    let mut ops = Vec::new();
    for (key, value) in new {
        let child = format!("{path}/{}", escape_pointer(key));
        match old.get(key) { Some(previous) if previous == value => {}, Some(previous) => ops.extend(diff_values(previous, value, &child)), None => ops.push(json!({"op":"add","path":child,"value":value})) }
    }
    ops
}

fn escape_pointer(value: &str) -> String { value.replace('~', "~0").replace('/', "~1") }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn batching_waits_for_window_and_coalesces() {
        let start = Instant::now();
        let mut batch = Batcher::new(Duration::from_millis(20));
        batch.push(start);
        assert!(!batch.due(start + Duration::from_millis(19)));
        assert!(batch.due(start + Duration::from_millis(20)));
        batch.push(start + Duration::from_millis(1));
        assert_eq!(batch.deadline, Some(start + Duration::from_millis(20)));
        let mut state = StreamState::from_snapshot(Snapshot { sequence: 0, task: json!({}) }).expect("snapshot");
        state.add_partial(json!({"metrics":{"a":1}})).expect("partial");
        state.add_partial(json!({"metrics":{"b":2}})).expect("partial");
        assert_eq!(state.desired, json!({"metrics":{"a":1,"b":2}}));
    }

    #[test]
    fn resync_rebases_to_snapshot_without_losing_desired_state() {
        let mut state = StreamState::from_snapshot(Snapshot { sequence: 4, task: json!({"done": 1}) }).expect("snapshot");
        state.add_partial(json!({"done": 2})).expect("partial");
        state.batch.force();
        state.in_flight = Some(state.desired.clone());
        state.batch.clear();
        state.resync(Snapshot { sequence: 7, task: json!({"done": 1, "note":"server"}) }).expect("resync");
        assert_eq!(state.sequence, 7);
        assert!(state.in_flight.is_none());
        assert_eq!(diff_values(&state.acknowledged, &state.desired, "/task").len(), 1);
    }

    #[test]
    fn fenced_epoch_stops_the_producer_rather_than_retrying() {
        // The earlier test asserted only how relay_error formats a string, so deleting the
        // stop entirely left all 179 tests green.
        for code in ["lease_conflict", "fenced_epoch"] {
            let frame = RelayFrame { kind: "error".into(), code: Some(code.into()), ..RelayFrame::default() };
            match frame_action(&frame) {
                FrameAction::Stop(reason) => assert!(reason.contains(code), "{reason}"),
                other => panic!("{code} produced {other:?} instead of a stop"),
            }
        }
    }

    #[test]
    fn a_resync_error_recovers_instead_of_stopping() {
        let frame = RelayFrame { kind: "error".into(), code: Some("resync_required".into()), ..RelayFrame::default() };
        assert_eq!(frame_action(&frame), FrameAction::Resync);
    }

    #[test]
    fn fenced_epoch_is_a_stop_signal() {
        assert_eq!(relay_error(Some("lease_conflict")), "panel relay stopped: lease_conflict");
        assert_eq!(relay_error(Some("fenced_epoch")), "panel relay stopped: fenced_epoch");
    }
}
