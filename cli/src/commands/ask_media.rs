// Purpose: Parse, validate, and upload per-option images for the ask command.
// Exports: resolve_option_media, upload_attachment, OptionImage,
//          OptionMediaError, parse_option_images, validate_option_image_labels,
//          is_remote_url, option_media_entry.
// Dependencies: crate::client, super::ask::ChoicePayload, serde_json.

use super::ask::ChoicePayload;
use crate::client::HiBossClient;
use serde_json::Value;
use std::collections::HashSet;
use std::error::Error;
use std::fmt::{Display, Formatter};

const MAX_OPTION_IMAGES: usize = 5;

/// One `--option-image LABEL=PATH_OR_URL` pair, split at the first '='.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct OptionImage {
    pub(crate) label: String,
    pub(crate) source: String,
}

#[derive(Debug, PartialEq)]
pub(crate) enum OptionMediaError {
    Invalid,
    TooMany,
    DuplicateLabel(String),
    UnknownLabel(String),
}

impl Display for OptionMediaError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Invalid => write!(
                formatter,
                "option images must use LABEL=PATH_OR_URL with non-empty values"
            ),
            Self::TooMany => write!(
                formatter,
                "a message can contain at most {MAX_OPTION_IMAGES} option images"
            ),
            Self::DuplicateLabel(label) => {
                write!(formatter, "duplicate option image label: {label}")
            }
            Self::UnknownLabel(label) => write!(
                formatter,
                "option image label '{label}' must match one of the --option/--action labels"
            ),
        }
    }
}

impl Error for OptionMediaError {}

/// Split each value at its first '=' and reject empty sides or repeated labels.
pub(crate) fn parse_option_images(raw: &[String]) -> Result<Vec<OptionImage>, OptionMediaError> {
    if raw.len() > MAX_OPTION_IMAGES {
        return Err(OptionMediaError::TooMany);
    }
    let mut seen = HashSet::with_capacity(raw.len());
    let mut images = Vec::with_capacity(raw.len());
    for value in raw {
        let (label, source) = value.split_once('=').ok_or(OptionMediaError::Invalid)?;
        let label = label.trim();
        let source = source.trim();
        if label.is_empty() || source.is_empty() {
            return Err(OptionMediaError::Invalid);
        }
        if !seen.insert(label.to_owned()) {
            return Err(OptionMediaError::DuplicateLabel(label.to_owned()));
        }
        images.push(OptionImage {
            label: label.to_owned(),
            source: source.to_owned(),
        });
    }
    Ok(images)
}

/// Every image label must name a real --option/--action label.
pub(crate) fn validate_option_image_labels(
    images: &[OptionImage],
    choices: &ChoicePayload,
) -> Result<(), OptionMediaError> {
    let labels = choices.options.as_deref().unwrap_or(&[]);
    for image in images {
        if !labels.iter().any(|label| label == &image.label) {
            return Err(OptionMediaError::UnknownLabel(image.label.clone()));
        }
    }
    Ok(())
}

/// An http(s) URL is sent through untouched; anything else is a local path to upload.
pub(crate) fn is_remote_url(source: &str) -> bool {
    let lower = source.to_ascii_lowercase();
    lower.starts_with("http://") || lower.starts_with("https://")
}

pub(crate) fn option_media_entry(label: &str, url: &str) -> Value {
    serde_json::json!({ "label": label, "url": url })
}

/// Validate all labels before a single byte is uploaded, then resolve each image.
pub(crate) async fn resolve_option_media(
    client: &HiBossClient,
    raw: &[String],
    choices: &ChoicePayload,
) -> Result<Option<Vec<Value>>, Box<dyn Error>> {
    let images = parse_option_images(raw)?;
    validate_option_image_labels(&images, choices)?;
    if images.is_empty() {
        return Ok(None);
    }
    let mut media = Vec::with_capacity(images.len());
    for image in &images {
        let url = if is_remote_url(&image.source) {
            image.source.clone()
        } else {
            client.upload_file(&image.source).await?.url
        };
        eprintln!("attached: {} -> {}", image.label, url);
        media.push(option_media_entry(&image.label, &url));
    }
    Ok(Some(media))
}

pub(crate) async fn upload_attachment(
    client: &HiBossClient,
    path: Option<&str>,
) -> Result<Option<String>, Box<dyn Error>> {
    let Some(path) = path else { return Ok(None) };
    let upload = client.upload_file(path).await?;
    eprintln!("Uploaded: {} ({})", upload.filename, upload.url);
    Ok(Some(upload.url))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn choices(labels: &[&str]) -> ChoicePayload {
        ChoicePayload {
            options: Some(labels.iter().map(|s| (*s).to_owned()).collect()),
            actions: HashMap::new(),
            default_option: None,
        }
    }

    #[test]
    fn split_happens_at_the_first_equals_sign() {
        let images =
            parse_option_images(&["A=./after.png?a=b=c".to_owned()]).expect("valid option image");
        assert_eq!(
            images,
            vec![OptionImage {
                label: "A".to_owned(),
                source: "./after.png?a=b=c".to_owned(),
            }]
        );
    }

    #[test]
    fn label_and_source_are_trimmed() {
        let images =
            parse_option_images(&["  A  =  ./after.png  ".to_owned()]).expect("valid option image");
        assert_eq!(images[0].label, "A");
        assert_eq!(images[0].source, "./after.png");
    }

    #[test]
    fn missing_equals_is_rejected() {
        let result = parse_option_images(&["A./after.png".to_owned()]);
        assert_eq!(result, Err(OptionMediaError::Invalid));
    }

    #[test]
    fn empty_label_or_source_is_rejected() {
        assert_eq!(
            parse_option_images(&["=./after.png".to_owned()]),
            Err(OptionMediaError::Invalid)
        );
        assert_eq!(
            parse_option_images(&["A=".to_owned()]),
            Err(OptionMediaError::Invalid)
        );
    }

    #[test]
    fn more_than_five_option_images_are_rejected() {
        let raw: Vec<String> = (0..6).map(|i| format!("option{i}=./{i}.png")).collect();
        assert_eq!(parse_option_images(&raw), Err(OptionMediaError::TooMany));
    }

    #[test]
    fn duplicate_labels_are_rejected() {
        let raw = vec!["A=./one.png".to_owned(), "A=./two.png".to_owned()];
        assert_eq!(
            parse_option_images(&raw),
            Err(OptionMediaError::DuplicateLabel("A".to_owned()))
        );
    }

    #[test]
    fn remote_urls_are_detected_case_insensitively() {
        assert!(is_remote_url("https://example.com/a.png"));
        assert!(is_remote_url("HTTP://example.com/a.png"));
        assert!(!is_remote_url("./a.png"));
        assert!(!is_remote_url("ftp://example.com/a.png"));
    }

    #[test]
    fn known_labels_pass_validation() {
        let images = parse_option_images(&["B=./b.png".to_owned()]).expect("valid");
        assert!(validate_option_image_labels(&images, &choices(&["A", "B"])).is_ok());
    }

    #[test]
    fn unknown_label_is_rejected() {
        let images = parse_option_images(&["Z=./z.png".to_owned()]).expect("valid");
        assert_eq!(
            validate_option_image_labels(&images, &choices(&["A", "B"])),
            Err(OptionMediaError::UnknownLabel("Z".to_owned()))
        );
    }

    #[test]
    fn label_must_match_when_no_choices_exist() {
        let images = parse_option_images(&["A=./a.png".to_owned()]).expect("valid");
        assert_eq!(
            validate_option_image_labels(&images, &choices(&[])),
            Err(OptionMediaError::UnknownLabel("A".to_owned()))
        );
    }

    #[test]
    fn payload_entry_shape_is_label_and_url_only() {
        let entry = option_media_entry(
            "压缩文案",
            "https://hiboss.example/api/attachments/abc.png",
        );
        assert_eq!(
            entry,
            serde_json::json!({
                "label": "压缩文案",
                "url": "https://hiboss.example/api/attachments/abc.png",
            })
        );
        assert_eq!(entry.as_object().map(|o| o.len()), Some(2));
    }
}
