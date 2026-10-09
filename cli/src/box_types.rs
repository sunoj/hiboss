// Purpose: Typed Box metadata and request/response contracts matching the server.
// Exports: Box kinds, author provenance, metadata, pages and filters.
// Dependencies: serde and clap.
use clap::ValueEnum;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum BoxKind {
    Link,
    Text,
    Image,
    Video,
    File,
}

impl BoxKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Link => "link",
            Self::Text => "text",
            Self::Image => "image",
            Self::Video => "video",
            Self::File => "file",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum BoxBy {
    Boss,
    Agent,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum BoxAuthor {
    Boss,
    Agent { id: String, name: String },
}

#[derive(Debug, Deserialize, Serialize)]
pub struct BoxItem {
    pub id: String,
    pub boss_id: String,
    pub boss_name: String,
    pub added_by: BoxAuthor,
    pub kind: BoxKind,
    pub text: Option<String>,
    pub url: Option<String>,
    pub note: Option<String>,
    pub project: Option<String>,
    pub tags: Vec<String>,
    pub source: String,
    pub media_type: Option<String>,
    pub media_bytes: Option<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u64>,
    pub created_at: String,
    pub has_media: bool,
}

#[derive(Debug, Serialize)]
pub struct BoxMetadata<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub boss: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<&'a str>,
    pub note: Option<&'a str>,
    pub project: Option<&'a str>,
    pub tags: &'a [String],
    pub source: &'static str,
}

#[derive(Debug, Deserialize)]
pub struct BoxPage {
    pub items: Vec<BoxItem>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Default, Serialize)]
pub struct BoxFilter<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<BoxKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub since: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub boss: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub by: Option<BoxBy>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<&'a str>,
}
