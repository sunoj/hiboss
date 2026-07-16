// Purpose: Support blocking hiboss requests where the agent waits for a boss reply.
// Exports: AskArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use crate::{client::HiBossClient, config::Config, helpers::unescape_body, session, types::SendRequest};
use clap::{ArgAction, Args};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::fmt::{Display, Formatter};

const MAX_CHOICES: usize = 5;

#[derive(Debug, Args)]
pub struct AskArgs {
    #[arg(long, default_value_t = 1800)]
    pub timeout: u32,
    #[arg(long, help = "Override channel (skips server-side channel_routing)")]
    pub channel: Option<String>,
    #[arg(
        long = "option",
        action = ArgAction::Append,
        conflicts_with = "actions",
        value_name = "TEXT",
        help = "Quick-reply option; repeat for each choice (commas are preserved)"
    )]
    pub options: Vec<String>,
    #[arg(
        long = "options",
        hide = true,
        value_name = "REMOVED",
        value_parser = reject_legacy_options
    )]
    legacy_options: Option<String>,
    #[arg(
        long = "action",
        action = ArgAction::Append,
        conflicts_with = "options",
        value_name = "LABEL=COMMAND",
        help = "Action button; repeat for each label and command"
    )]
    pub actions: Vec<String>,
    #[arg(
        long = "actions",
        hide = true,
        value_name = "REMOVED",
        value_parser = reject_legacy_actions
    )]
    legacy_actions: Option<String>,
    #[arg(long, help = "Local file to upload and attach")]
    pub file: Option<String>,
    #[arg(long, help = "Target agent name or ID for agent-to-agent messaging")]
    pub to: Option<String>,
    #[arg(value_name = "body")]
    pub body: String,
}

fn reject_legacy_options(_: &str) -> Result<String, String> {
    Err(
        "--options was removed because comma-separated choices are ambiguous; repeat --option once per choice, for example: --option \"A\" --option \"B\""
            .to_owned(),
    )
}

fn reject_legacy_actions(_: &str) -> Result<String, String> {
    Err(
        "--actions was removed; repeat --action once per LABEL=COMMAND pair, for example: --action \"Approve=deploy\" --action \"Reject=echo no\""
            .to_owned(),
    )
}

#[derive(Debug)]
pub(crate) struct ChoicePayload {
    pub(crate) options: Option<Vec<String>>,
    pub(crate) actions: HashMap<String, Value>,
}

#[derive(Debug)]
pub(crate) enum AskInputError {
    EmptyChoice,
    InvalidAction,
    MixedChoiceTypes,
    TooManyChoices,
    DuplicateChoice(String),
}

impl Display for AskInputError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyChoice => write!(formatter, "options and action labels cannot be empty"),
            Self::InvalidAction => write!(formatter, "actions must use LABEL=COMMAND with non-empty values"),
            Self::MixedChoiceTypes => write!(formatter, "--option and --action cannot be combined"),
            Self::TooManyChoices => write!(formatter, "a message can contain at most {MAX_CHOICES} choices"),
            Self::DuplicateChoice(choice) => write!(formatter, "duplicate choice: {choice}"),
        }
    }
}

impl Error for AskInputError {}

impl AskArgs {
    pub(crate) fn choice_payload(&self) -> Result<ChoicePayload, AskInputError> {
        if !self.options.is_empty() && !self.actions.is_empty() {
            return Err(AskInputError::MixedChoiceTypes);
        }
        if !self.actions.is_empty() {
            return parse_actions(&self.actions);
        }
        let options = normalize_choices(&self.options)?;
        Ok(ChoicePayload { options, actions: HashMap::new() })
    }
}

fn parse_actions(values: &[String]) -> Result<ChoicePayload, AskInputError> {
    let mut labels = Vec::with_capacity(values.len());
    let mut actions = HashMap::with_capacity(values.len());
    for value in values {
        let (label, command) = value.split_once('=').ok_or(AskInputError::InvalidAction)?;
        let label = label.trim();
        let command = command.trim();
        if label.is_empty() || command.is_empty() {
            return Err(AskInputError::InvalidAction);
        }
        labels.push(label.to_owned());
        actions.insert(label.to_owned(), Value::String(command.to_owned()));
    }
    let options = normalize_choices(&labels)?;
    Ok(ChoicePayload { options, actions })
}

fn normalize_choices(values: &[String]) -> Result<Option<Vec<String>>, AskInputError> {
    if values.is_empty() {
        return Ok(None);
    }
    if values.len() > MAX_CHOICES {
        return Err(AskInputError::TooManyChoices);
    }
    let mut seen = HashSet::with_capacity(values.len());
    let mut choices = Vec::with_capacity(values.len());
    for value in values {
        let choice = value.trim();
        if choice.is_empty() {
            return Err(AskInputError::EmptyChoice);
        }
        if !seen.insert(choice.to_owned()) {
            return Err(AskInputError::DuplicateChoice(choice.to_owned()));
        }
        choices.push(choice.to_owned());
    }
    Ok(Some(choices))
}

pub async fn run(args: &AskArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    if args.to.is_none() {
        warn_unread_messages(client).await;
    }
    let choices = args.choice_payload()?;
    let file_url = upload_attachment(client, args.file.as_deref()).await?;
    let request = SendRequest {
        body: unescape_body(&args.body),
        mode: "blocking".to_owned(),
        priority: "normal".to_owned(),
        channel: args.channel.clone(),
        metadata: action_metadata(&choices.actions)?,
        options: choices.options,
        file_url,
        message_type: None,
        session_id: session::read_session_id(),
        to: args.to.clone(),
    };
    session::mark_asked();
    let submission = client.send_message(&request).await?;
    eprintln!(
        "[ask {}] sent, waiting up to {}s for reply (recover anytime via: hiboss status {})",
        submission.id, args.timeout, submission.id
    );
    let poll = client.poll_reply(&submission.id, args.timeout).await?;
    print_poll_result(&submission.id, poll.replies.as_deref(), client).await
}

async fn upload_attachment(
    client: &HiBossClient,
    path: Option<&str>,
) -> Result<Option<String>, Box<dyn Error>> {
    let Some(path) = path else { return Ok(None) };
    let upload = client.upload_file(path).await?;
    eprintln!("Uploaded: {} ({})", upload.filename, upload.url);
    Ok(Some(upload.url))
}

fn action_metadata(actions: &HashMap<String, Value>) -> Result<Option<HashMap<String, Value>>, serde_json::Error> {
    if actions.is_empty() {
        return Ok(None);
    }
    let mut metadata = HashMap::new();
    metadata.insert("actions".to_owned(), serde_json::to_value(actions)?);
    Ok(Some(metadata))
}

async fn print_poll_result(
    submission_id: &str,
    replies: Option<&[crate::types::Message]>,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    if let Some(replies) = replies {
        if let Some(reply) = replies.first() {
            let _ = client.update_status(&reply.id, "read").await;
            if let Some(meta) = &reply.metadata {
                if let Some(Value::String(action_cmd)) = meta.get("action") {
                    if let Some(body) = &reply.body {
                        println!("{}", body);
                    }
                    eprintln!("Action: {}", action_cmd);
                    return Ok(());
                }
            }
            if let Some(body) = &reply.body {
                println!("{}", body);
                if crate::session::should_show_ack_hint() {
                    let id_short = &reply.id[..8.min(reply.id.len())];
                    eprintln!(
                        "[reply {}] Acknowledge via: hiboss send \"<your response>\" or hiboss react {} 👍",
                        id_short, id_short
                    );
                }
                return Ok(());
            }
        }
    }
    eprintln!("No reply yet");
    println!("{submission_id}");
    Ok(())
}

/// Check for unread boss messages before sending. Warns via stdout so the AI sees it.
async fn warn_unread_messages(client: &HiBossClient) {
    let sid = crate::session::read_session_id();
    let boss_count = client.inbox_count(None, sid.as_deref()).await.unwrap_or(0);
    let a2a_count = client.inbox_count_a2a(sid.as_deref()).await.unwrap_or(0);
    if boss_count > 0 || a2a_count > 0 {
        if boss_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread boss message(s). Read them FIRST: hiboss inbox",
                boss_count
            );
        }
        if a2a_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread peer message(s). Read them FIRST: hiboss inbox --direction agent_to_agent",
                a2a_count
            );
        }
        println!("Reply to unread messages with: hiboss reply <id> \"response\" BEFORE sending new messages.");
    }
}
