// Purpose: Build the read-only status report: stored message state plus classified replies.
// Exports: StatusReport, ReplyReport, ReplyOutcome (serializable) and StatusReport::text().
// Dependencies: serde, serde_json, crate::types::Message, crate::message_security.

use crate::message_security::assurance_label;
use crate::types::Message;
use serde::Serialize;
use serde_json::Value;

const AUTO_DEFAULT_NOTE: &str =
    "Automatic timeout default recorded by the server; not a boss reply or execution authorization.";

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ReplyOutcome {
    Reply,
    AutoDefault,
}

#[derive(Debug, Serialize)]
pub(crate) struct ReplyReport {
    pub reply_id: String,
    pub body: Option<String>,
    pub outcome: ReplyOutcome,
    pub action: Option<String>,
    /// Verified provenance label, e.g. `ios/verified`, `api/not_configured`, `agent`.
    pub assurance: String,
}

/// Stored server state only: `status` is the raw technical value, never an approval.
#[derive(Debug, Serialize)]
pub(crate) struct StatusReport {
    pub message_id: String,
    pub direction: Option<String>,
    pub status: Option<String>,
    pub replies: Vec<ReplyReport>,
    #[serde(skip)]
    options_expired: bool,
}

fn metadata_field<'a>(message: &'a Message, key: &str) -> Option<&'a Value> {
    message.metadata.as_ref().and_then(|meta| meta.get(key))
}

impl ReplyReport {
    /// Only an explicit `metadata.auto_default == true` marks an automatic default,
    /// and an automatic default never carries an action.
    pub(crate) fn from_reply(reply: &Message) -> Self {
        let automatic = metadata_field(reply, "auto_default").and_then(Value::as_bool) == Some(true);
        let action = if automatic {
            None
        } else {
            metadata_field(reply, "action").and_then(Value::as_str).map(str::to_owned)
        };
        let outcome = if automatic { ReplyOutcome::AutoDefault } else { ReplyOutcome::Reply };
        Self {
            reply_id: reply.id.clone(),
            body: reply.body.clone(),
            outcome,
            action,
            assurance: assurance_label(reply),
        }
    }

    fn text(&self) -> String {
        let body = self.body.as_deref().unwrap_or("-");
        let source = format!("  Source: {}\n", self.assurance);
        match self.outcome {
            ReplyOutcome::AutoDefault => format!(
                "Reply {} [auto_default]: {body}\n{source}  {AUTO_DEFAULT_NOTE}\n",
                self.reply_id
            ),
            ReplyOutcome::Reply => {
                let action = self.action.as_deref().map(|a| format!("  Action: {a}\n"));
                let action = action.unwrap_or_default();
                format!("Reply {} [reply]: {body}\n{source}{action}", self.reply_id)
            }
        }
    }
}

impl StatusReport {
    pub(crate) fn from_message(message: &Message) -> Self {
        let replies = message.replies.as_deref().unwrap_or_default();
        Self {
            message_id: message.id.clone(),
            direction: message.direction.clone(),
            status: message.status.clone(),
            replies: replies.iter().map(ReplyReport::from_reply).collect(),
            options_expired: metadata_field(message, "options_expired").and_then(Value::as_bool)
                == Some(true),
        }
    }

    pub(crate) fn text(&self) -> String {
        let mut out = format!("Message: {}\n", self.message_id);
        out.push_str(&format!("Direction: {}\n", self.direction.as_deref().unwrap_or("unknown")));
        out.push_str(&format!(
            "Status: {} (stored message state)\n",
            self.status.as_deref().unwrap_or("unknown"),
        ));
        if self.options_expired {
            out.push_str("Options: expired\n");
        }
        if self.replies.is_empty() {
            out.push_str("Replies: none recorded\n");
        }
        for reply in &self.replies {
            out.push_str(&reply.text());
        }
        out
    }
}

#[cfg(test)]
#[path = "status_result_tests.rs"]
mod tests;
