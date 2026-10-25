// Formats ask outcomes without presenting timeout defaults as boss approval.
// Exports a serializable result and its text representation; depends on ask_support.

use super::ask::ChoicePayload;
use super::ask_support::resolve_default_reply;
use crate::types::Message;
use serde::Serialize;
use std::error::Error;

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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_label: Option<String>,
}

/// The reply that answers `ask`: a boss_to_agent row for a boss ask, a peer's row for an
/// agent-to-agent ask. The asker's own follow-ups and forward copies never answer it.
pub(crate) fn decision_reply(ask: &Message) -> Option<&Message> {
    let peer_ask = ask.direction.as_deref() == Some("agent_to_agent");
    ask.replies.as_deref()?.iter().find(|reply| {
        if peer_ask {
            reply.direction.as_deref() == Some("agent_to_agent")
                && reply.agent_id.is_some()
                && reply.agent_id != ask.agent_id
        } else {
            reply.direction.as_deref() == Some("boss_to_agent")
        }
    })
}

impl AskResult {
    pub(crate) fn from_poll(
        message_id: &str,
        ask: Option<&Message>,
        choices: &ChoicePayload,
    ) -> Self {
        let mut result = Self {
            message_id: message_id.to_owned(),
            reply_id: None,
            outcome: Outcome::Timeout,
            body: None,
            action: None,
            device_label: None,
        };
        let answer = ask.and_then(decision_reply);
        if let Some(reply) = answer {
            let automatic = reply
                .metadata
                .as_ref()
                .and_then(|meta| meta.get("auto_default"))
                .and_then(|value| value.as_bool())
                == Some(true);
            result.device_label = super::status_result::device_label(reply);
            result.reply_id = Some(reply.id.clone());
            result.body = reply.body.clone();
            result.outcome = if automatic {
                Outcome::AutoDefault
            } else {
                Outcome::Reply
            };
            if !automatic {
                result.action = reply
                    .metadata
                    .as_ref()
                    .and_then(|meta| meta.get("action"))
                    .and_then(|value| value.as_str())
                    .map(str::to_owned);
            }
        } else if let Some(default) = resolve_default_reply(choices, answer) {
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

pub(crate) fn print_result(result: &AskResult, json: bool) -> Result<(), Box<dyn Error>> {
    if json {
        println!("{}", serde_json::to_string(result)?);
        return Ok(());
    }
    println!("{}", result.text());
    if let Some(action) = &result.action {
        eprintln!("Action: {}", action);
    } else if result.outcome == Outcome::Reply && crate::session::should_show_ack_hint() {
        if let Some(id) = &result.reply_id {
            eprintln!("{}", acknowledgement_hint(id));
        }
    } else if result.outcome == Outcome::Timeout {
        eprintln!("No reply yet");
    }
    Ok(())
}

fn acknowledgement_hint(id: &str) -> String {
    format!(
        "[reply {id}] Acknowledge via: hiboss reply {id} \"<your response>\" or hiboss react {id} 👍"
    )
}

#[cfg(test)]
#[path = "ask_result_tests.rs"]
mod tests;
