// Wakes an idle Claude Code session when the boss writes to it, through the messaging
// socket Claude Code exports to the session's hooks. Sends fixed fields only, never a body.
// Exports Inbox, Probe, deliver, wake_notice, wake_for_unread_spool; deps: serde_json, sockets.

use crate::session;
use serde_json::Value;
use std::io;
use std::path::PathBuf;
use std::time::Duration;

const SOCKET_VAR: &str = "CLAUDE_CODE_MESSAGING_SOCKET";
const TOKEN_VAR: &str = "CLAUDE_CODE_MESSAGING_TOKEN";
const PUSH_TIMEOUT: Duration = Duration::from_secs(3);

/// The session's messaging socket as Claude Code exported it. The token stays in memory.
#[derive(Clone)]
pub(crate) struct Inbox {
    pub socket: PathBuf,
    token: String,
}

/// Whether the socket's owner is still there to be woken.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Probe {
    Alive,
    /// The socket file is gone or nothing listens on it: the Claude Code process exited.
    Gone,
    Unknown,
}

impl Inbox {
    pub fn from_env() -> Option<Self> {
        let socket = std::env::var_os(SOCKET_VAR).filter(|value| !value.is_empty())?;
        let token = std::env::var(TOKEN_VAR).ok().filter(|value| !value.is_empty())?;
        Some(Self { socket: PathBuf::from(socket), token })
    }

    /// Socket path of the current process's session, for comparing with a running daemon's.
    pub fn socket_from_env() -> Option<String> {
        Self::from_env().map(|inbox| inbox.socket.to_string_lossy().into_owned())
    }

    #[cfg(test)]
    pub fn new(socket: PathBuf, token: &str) -> Self {
        Self { socket, token: token.to_owned() }
    }

    /// Connects without writing: tells a live session from one whose process has exited.
    pub fn probe(&self) -> Probe {
        match std::os::unix::net::UnixStream::connect(&self.socket) {
            Ok(_) => Probe::Alive,
            Err(err) if is_gone(&err) => Probe::Gone,
            Err(_) => Probe::Unknown,
        }
    }

    /// Writes one user turn to the session, bounded so a stuck socket never holds the daemon.
    pub async fn push(&self, text: String) -> io::Result<()> {
        let inbox = self.clone();
        let write = tokio::task::spawn_blocking(move || inbox.write_notice(&text));
        match tokio::time::timeout(PUSH_TIMEOUT, write).await {
            Ok(Ok(result)) => result,
            Ok(Err(join)) => Err(io::Error::other(join)),
            Err(_) => Err(io::Error::new(io::ErrorKind::TimedOut, "session socket did not accept the notice")),
        }
    }

    fn write_notice(&self, text: &str) -> io::Result<()> {
        use std::io::Write;
        let mut stream = std::os::unix::net::UnixStream::connect(&self.socket)?;
        stream.set_write_timeout(Some(PUSH_TIMEOUT))?;
        let auth = serde_json::json!({"type": "auth", "token": self.token});
        let user = serde_json::json!({"type": "user", "message": {"role": "user", "content": text}});
        writeln!(stream, "{auth}")?;
        writeln!(stream, "{user}")?;
        stream.shutdown(std::net::Shutdown::Write)
    }
}

pub(crate) fn is_gone(err: &io::Error) -> bool {
    matches!(err.kind(), io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused)
}

/// The notice for a streamed message, or None when it must not wake this session: only a boss
/// message addressed to exactly this session does, and only while the session is idle.
pub(crate) fn wake_notice(message: &Value, session_id: Option<&str>) -> Option<String> {
    let notice = notice_for(message, session_id)?;
    let id = message["id"].as_str()?;
    // One push per message: a woken turn that ends without a tool call leaves it spooled, and
    // the next Stop must not wake the session for it again.
    if session::was_woken(id) {
        return None;
    }
    // One push per idle period: a woken turn that ends idle again re-arms it on Stop.
    session::take_idle()?;
    session::record_woken(id);
    Some(notice)
}

/// The notice a message would wake this session with, ignoring whether it is idle.
pub(crate) fn notice_for(message: &Value, session_id: Option<&str>) -> Option<String> {
    let session_id = session_id.filter(|id| !id.is_empty())?;
    if message["direction"] != "boss_to_agent" || message["target_session_id"] != session_id {
        return None;
    }
    let id = plain_id(message["id"].as_str()?)?;
    Some(notice_text(message, id))
}

fn notice_text(message: &Value, id: &str) -> String {
    let ack = format!("acknowledge with `hiboss reply {id} \"...\"` or `hiboss react {id} 👍`");
    match message["reply_to"].as_str().and_then(plain_id) {
        Some(ask) if message["metadata"]["auto_default"] == true => format!(
            "[hiboss] Your ask {ask} timed out while this session was idle, and the server selected its \
             default (message {id}). That is not a boss decision and authorizes nothing. \
             Read it with `hiboss status {ask}`."
        ),
        Some(ask) => format!(
            "[hiboss] The boss replied to your message {ask} while this session was idle (reply {id}). \
             Read it with `hiboss status {ask}`, then {ack}."
        ),
        None => format!(
            "[hiboss] The boss sent message {id} to this session while it was idle. \
             Read it with `hiboss inbox`, then {ack}."
        ),
    }
}

/// The one delivery path for the daemon's stream and an ask's waiter: spools the message (the
/// hook shows it on the next tool call) and wakes the session when it is addressed there and
/// idle. True when the session's process is gone.
pub(crate) async fn deliver(data: &str, inbox: Option<&Inbox>, session_id: Option<&str>) -> bool {
    // The spool holds bodies the hook injects into the agent context, so it is only ever
    // appended as a private file in the validated state directory.
    if let Some(line) = spool_line(data) {
        let _ = session::append_state(session::DAEMON_PENDING, &format!("{line}\n"));
    }
    let (Some(inbox), Ok(message)) = (inbox, serde_json::from_str::<Value>(data)) else {
        return false;
    };
    let Some(notice) = wake_notice(&message, session_id) else {
        return false;
    };
    match inbox.push(notice).await {
        Ok(()) => false,
        Err(err) => {
            eprintln!("hiboss: session wake not delivered: {err}");
            is_gone(&err)
        }
    }
}

/// The line the hook may inject for this stream event: only a message whose provenance
/// verifies, the same check `watch` and `bot` apply, so the spool never carries a forged body.
fn spool_line(data: &str) -> Option<String> {
    match crate::message_security::parse_verified_message(data) {
        Ok(_) => Some(data.to_owned()),
        Err(error) => {
            eprintln!("hiboss: blocked unverified message: {error}");
            None
        }
    }
}

/// Stop: a boss message spooled after the turn's last tool call was never shown, so the
/// session is woken for it now instead of waiting for the next one.
pub(crate) async fn wake_for_unread_spool(session_id: Option<&str>) {
    let (Some(inbox), Some(spool)) = (Inbox::from_env(), session::read_state(session::DAEMON_PENDING)) else {
        return;
    };
    let mut messages = spool.lines().filter_map(|line| serde_json::from_str::<Value>(line).ok());
    if let Some(notice) = messages.find_map(|message| wake_notice(&message, session_id))
        && let Err(err) = inbox.push(notice).await
    {
        eprintln!("hiboss: session wake not delivered: {err}");
    }
}

/// Message ids are server-generated; anything else is not interpolated into the notice.
fn plain_id(id: &str) -> Option<&str> {
    let plain = !id.is_empty() && id.len() <= 64
        && id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'));
    plain.then_some(id)
}

#[cfg(test)]
#[path = "daemon_wake_tests.rs"]
mod tests;
