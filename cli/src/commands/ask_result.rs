// Formats ask outcomes without presenting timeout defaults as boss approval.
// Exports a serializable result and its text representation; depends on ask_support.

use super::ask::ChoicePayload;
use super::ask_support::resolve_default_reply;
use crate::types::Message;
use serde::Serialize;

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Outcome {
    Reply,
    AutoDefault,
    LocalDefault,
    Timeout,
}

#[derive(Debug, Serialize)]
pub(crate) struct AskResult {
    pub message_id: String,
    pub reply_id: Option<String>,
    pub outcome: Outcome,
    pub body: Option<String>,
    pub action: Option<String>,
}

impl AskResult {
    pub(crate) fn from_poll(
        message_id: &str,
        replies: Option<&[Message]>,
        choices: &ChoicePayload,
    ) -> Self {
        let mut result = Self {
            message_id: message_id.to_owned(), reply_id: None,
            outcome: Outcome::Timeout, body: None, action: None,
        };
        if let Some(reply) = replies.and_then(|items| items.first()) {
            let automatic = reply.metadata.as_ref()
                .and_then(|meta| meta.get("auto_default"))
                .and_then(|value| value.as_bool()) == Some(true);
            result.reply_id = Some(reply.id.clone());
            result.body = reply.body.clone();
            result.outcome = if automatic { Outcome::AutoDefault } else { Outcome::Reply };
            if !automatic {
                result.action = reply.metadata.as_ref().and_then(|meta| meta.get("action"))
                    .and_then(|value| value.as_str()).map(str::to_owned);
            }
        } else if let Some(default) = resolve_default_reply(choices, replies) {
            result.outcome = Outcome::LocalDefault;
            result.body = Some(default.label);
        }
        result
    }

    pub(crate) fn text(&self) -> String {
        match self.outcome {
            Outcome::AutoDefault => format!(
                "[auto_default] {}\nAutomatic timeout default; not a boss reply or execution authorization.",
                self.body.as_deref().unwrap_or(""),
            ),
            Outcome::LocalDefault => format!(
                "[local_default] {}\nLocal timeout fallback; not a confirmed server selection or execution authorization.",
                self.body.as_deref().unwrap_or(""),
            ),
            Outcome::Reply => self.body.clone().unwrap_or_default(),
            Outcome::Timeout => self.message_id.clone(),
        }
    }
}

#[cfg(test)]
#[path = "ask_result_tests.rs"]
mod tests;
