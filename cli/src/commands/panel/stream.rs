// Purpose: Produce live panel state from NDJSON through the authenticated relay.
// Exports: PanelStreamArgs and run.
// Dependencies: clap, futures-util, tokio-tungstenite, serde_json, and HiBossClient.

use crate::{client::HiBossClient, session};
use super::relay_helpers::{live_epoch, relay_error};
use super::transport::{connect, diff_values, merge_object, new_id, parse_frame, receive_frame, release, same_value, snapshot_from, Connection, Reader, RelayFailure, RelayFrame, Snapshot, Writer};
use clap::Args;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::error::Error;
use std::time::{Duration, Instant};
use tokio::io::{self, AsyncBufReadExt};
use tokio::sync::mpsc;
use tokio::time::{sleep, sleep_until};
use tokio_tungstenite::tungstenite::Message;

const BATCH_WINDOW: Duration = Duration::from_millis(20);
const ACK_DRAIN_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_RECONNECTS: usize = 5;
#[derive(Debug, Args)]
pub struct PanelStreamArgs {
    #[arg(value_name = "PANEL_ID")]
    pub panel_id: String,
    #[arg(long, help = "Explicitly replace this currently active producer epoch")]
    pub takeover_epoch: Option<String>,
}

#[path = "stream_state.rs"]
mod state;
use state::StreamState;
#[cfg(test)]
use state::Batcher;

pub async fn run(args: &PanelStreamArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let panel = client.get_panel(&args.panel_id).await?;
    let revision = panel.get("definitionRevision").and_then(Value::as_u64).unwrap_or(1);
    let (mut connection, snapshot) = connect_with_recovery(client, &args.panel_id, revision, args.takeover_epoch.as_deref()).await?;
    session::write_panel_epoch(&args.panel_id, Some(&connection.epoch))?;
    let mut state = StreamState::from_snapshot(snapshot)?;
    let (tx, mut rx) = mpsc::channel::<Result<String, String>>(32);
    tokio::spawn(read_stdin(tx));
    let mut renewal = tokio::time::interval(Duration::from_secs(15));
    renewal.tick().await;
    let mut input_closed = false;
    let mut drain_deadline = None;

    loop {
        if input_closed && state.ambiguous && state.in_flight.is_none() { return Err("stream ended with unacknowledged work".into()); }
        if input_closed && state.finished() {
            release(&mut connection, &args.panel_id, revision).await?;
            session::write_panel_epoch(&args.panel_id, None)?;
            return Ok(());
        }
        let deadline = state.batch.deadline;
        let wake_at = deadline.map_or_else(Instant::now, |value| value);
        let drain_at = drain_deadline.map_or_else(Instant::now, |value| value);
        tokio::select! {
            _ = renewal.tick() => connection.writer.send(Message::Text(json!({"protocolVersion":2,"kind":"lease.renew","panelId":args.panel_id,"definitionRevision":revision,"epoch":connection.epoch}).to_string().into())).await?,
            line = rx.recv(), if !input_closed => match line {
                Some(Ok(line)) => if !line.trim().is_empty() { state.add_partial(serde_json::from_str(&line)?)?; },
                Some(Err(error)) => return Err(error.into()),
                None => { input_closed = true; if state.in_flight.is_some() { drain_deadline = Some(Instant::now() + ACK_DRAIN_TIMEOUT); } },
            },
            frame = connection.reader.next() => match frame {
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {
                    let (next, snapshot) = reconnect(client, &args.panel_id, revision, &connection.epoch).await?;
                    session::write_panel_epoch(&args.panel_id, Some(&next.epoch))?;
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

async fn connect_with_recovery(client: &HiBossClient, panel_id: &str, revision: u64, takeover: Option<&str>) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    match connect(client, panel_id, revision, takeover).await {
        Ok(value) => Ok(value),
        Err(error) if error.downcast_ref::<RelayFailure>().is_some_and(|failure| failure.code == "lease_conflict") => {
            let state = client.panel_state(panel_id).await?;
            let recorded = session::read_panel_epoch(panel_id);
            let live = live_epoch(&state);
            if live.is_some() && live == recorded {
                return connect(client, panel_id, revision, live.as_deref()).await;
            }
            let exact = live.map_or_else(|| "<live-epoch>".to_owned(), |epoch| epoch.to_owned());
            Err(format!("panel lease_conflict: live epoch is {exact}; inspect it and retry with `hiboss panel stream {panel_id} --takeover-epoch {exact}`").into())
        }
        Err(error) => Err(error),
    }
}

async fn reconnect(client: &HiBossClient, panel_id: &str, revision: u64, epoch: &str) -> Result<(Connection, Snapshot), Box<dyn Error>> {
    for attempt in 0..MAX_RECONNECTS {
        match connect(client, panel_id, revision, Some(epoch)).await {
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
            connection.writer.send(Message::Text(json!({"protocolVersion":2,"kind":"subscribe","panelId":panel_id}).to_string().into())).await?;
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
/// makes two agents thrash and the panel flicker between them, which is a decision property.
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

async fn receive_snapshot(reader: &mut Reader) -> Result<Snapshot, Box<dyn Error>> {
    loop {
        let frame = receive_frame(reader, "resync").await?;
        if frame.kind == "state.snapshot" { return snapshot_from(frame); }
        if frame.kind == "error" { return Err(relay_error(frame.code.as_deref()).into()); }
    }
}
async fn send_update(writer: &mut Writer, state: &mut StreamState, panel_id: &str, revision: u64, epoch: &str) -> Result<(), Box<dyn Error>> {
    let ops = diff_values(&state.acknowledged, &state.desired, "/task");
    let kind = if ops.is_empty() { "state.unchanged" } else { "state.update" };
    state.in_flight = Some(state.desired.clone());
    state.batch.clear();
    let update = json!({"protocolVersion":2,"kind":kind,"panelId":panel_id,"definitionRevision":revision,"epoch":epoch,"updateId":new_id(),"baseSequence":state.sequence,"ops":ops});
    writer.send(Message::Text(serde_json::to_string(&update)?.into())).await?;
    Ok(())
}


#[cfg(test)]
#[path = "stream_tests.rs"]
mod tests;
