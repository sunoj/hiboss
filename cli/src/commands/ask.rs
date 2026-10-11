// Purpose: Support blocking hiboss requests where the agent waits for a boss reply.
// Exports: AskArgs and run().
// Dependencies: clap, crate::client, crate::config, crate::types.

use super::ask_media::{resolve_option_media, upload_attachment};
use super::ask_result::{AskResult, print_result};
use super::ask_support::{action_metadata, validate_default_option, warn_unread_messages};
use super::ask_wait::wait_for_reply;
use crate::{client::HiBossClient, config::Config, session, types::SendRequest};
use clap::{ArgAction, Args};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::fmt::{Display, Formatter};

const MAX_CHOICES: usize = 5;

#[derive(Debug, Args)]
pub struct AskArgs {
    #[arg(long, default_value_t = 1800, value_parser = clap::value_parser!(u32).range(60..=86400))]
    pub timeout: u32,
    #[arg(
        long,
        help = "Print a JSON result with reply, auto_default, local_default, or timeout outcome"
    )]
    pub json: bool,
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
    #[arg(
        long = "default",
        value_name = "LABEL",
        help = "Select LABEL on timeout; automatic defaults are not execution authorization"
    )]
    pub default_option: Option<String>,
    #[arg(
        long = "option-image",
        action = ArgAction::Append,
        value_name = "LABEL=PATH_OR_URL",
        help = "Image for a choice label; repeat per option (local path or http(s) URL)"
    )]
    pub option_images: Vec<String>,
    #[arg(long, help = "Local file to upload and attach")]
    pub file: Option<String>,
    #[arg(long, help = "Target agent name or ID for agent-to-agent messaging")]
    pub to: Option<String>,
    #[arg(
        long,
        default_value = "normal",
        help = "Message priority: critical, high, normal, or low"
    )]
    pub priority: String,
    #[arg(
        long,
        help = "Short non-sensitive summary shown in private-mode push notifications"
    )]
    pub summary: Option<String>,
    #[arg(
        long,
        conflicts_with = "content_file",
        help = "Markdown message details beneath the short title"
    )]
    pub content: Option<String>,
    #[arg(
        long,
        conflicts_with = "content",
        help = "UTF-8 Markdown file containing the complete message details"
    )]
    pub content_file: Option<std::path::PathBuf>,
    #[arg(
        value_name = "title",
        help = "Short title, at most 144 Unicode characters"
    )]
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
    pub(crate) default_option: Option<String>,
}

#[derive(Debug)]
pub(crate) enum AskInputError {
    EmptyChoice,
    InvalidAction,
    MixedChoiceTypes,
    TooManyChoices,
    DuplicateChoice(String),
    DefaultNotInChoices(String),
}

impl Display for AskInputError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyChoice => write!(formatter, "options and action labels cannot be empty"),
            Self::InvalidAction => write!(
                formatter,
                "actions must use LABEL=COMMAND with non-empty values"
            ),
            Self::MixedChoiceTypes => write!(formatter, "--option and --action cannot be combined"),
            Self::TooManyChoices => write!(
                formatter,
                "a message can contain at most {MAX_CHOICES} choices"
            ),
            Self::DuplicateChoice(choice) => write!(formatter, "duplicate choice: {choice}"),
            Self::DefaultNotInChoices(label) => write!(
                formatter,
                "--default '{label}' must match one of the --option/--action labels"
            ),
        }
    }
}

impl Error for AskInputError {}

impl AskArgs {
    pub(crate) fn choice_payload(&self) -> Result<ChoicePayload, AskInputError> {
        if !self.options.is_empty() && !self.actions.is_empty() {
            return Err(AskInputError::MixedChoiceTypes);
        }
        let mut payload = if !self.actions.is_empty() {
            let partial = parse_actions(&self.actions)?;
            ChoicePayload {
                options: partial.options,
                actions: partial.actions,
                default_option: None,
            }
        } else {
            ChoicePayload {
                options: normalize_choices(&self.options)?,
                actions: HashMap::new(),
                default_option: None,
            }
        };
        payload.default_option =
            validate_default_option(&self.default_option, payload.options.as_deref())?;
        Ok(payload)
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
    Ok(ChoicePayload {
        options,
        actions,
        default_option: None,
    })
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

pub async fn run(
    args: &AskArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let choices = args.choice_payload()?;
    let mut request = prepare_request(args, client, &choices).await?;
    if args.to.is_none() && !args.json {
        warn_unread_messages(client).await;
    }
    session::mark_asked();
    let submission = super::session_register::send_with_session_heal(client, &mut request).await?;
    eprintln!(
        "[ask {}] sent, waiting up to {}s for reply (recover anytime via: hiboss status {})",
        submission.id, args.timeout, submission.id
    );
    let poll = wait_for_reply(client, &submission.id, args.timeout).await?;
    let replies = poll.as_ref().and_then(|message| message.replies.as_deref());
    let result = AskResult::from_poll(&submission.id, replies, &choices);
    if let Some(reply_id) = &result.reply_id {
        let _ = client.update_status(reply_id, "read").await;
    }
    print_result(&result, args.json)
}

async fn prepare_request(
    args: &AskArgs,
    client: &HiBossClient,
    choices: &ChoicePayload,
) -> Result<SendRequest, Box<dyn Error>> {
    let title = super::message_text::title(&args.body, args.to.is_some())?;
    let content =
        super::message_text::content(args.content.as_deref(), args.content_file.as_deref())?;
    let option_media = resolve_option_media(client, &args.option_images, choices).await?;
    let file_url = upload_attachment(client, args.file.as_deref()).await?;
    Ok(SendRequest {
        body: title,
        mode: "blocking".to_owned(),
        timeout: Some(args.timeout),
        priority: args.priority.clone(),
        channel: args.channel.clone(),
        metadata: action_metadata(
            &choices.actions,
            choices.default_option.as_deref(),
            args.summary.as_deref(),
            content.as_deref(),
            option_media,
        )?,
        options: choices.options.clone(),
        file_url,
        message_type: None,
        session_id: session::read_session_id(),
        to: args.to.clone(),
    })
}
