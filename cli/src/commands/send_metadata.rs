// Builds the complete Markdown content and structured context of a send request.
// Exports build_metadata; body content never comes from the private push summary.
// Dependencies: SendArgs, message text loading, and serde_json.

use super::send::SendArgs;
use serde_json::Value;
use std::{collections::HashMap, error::Error};

pub(crate) fn build_metadata(args: &SendArgs) -> Result<Option<HashMap<String, Value>>, Box<dyn Error>> {
    let content = super::message_text::content(args.content.as_deref(), args.content_file.as_deref())?;
    let has_context = args.task.is_some() || args.files.is_some() || args.branch.is_some();
    let mut meta = super::message_text::metadata_fields([
        ("summary", args.summary.as_ref().map(|s| Value::String(s.clone()))),
        ("content", content.filter(|s| !s.is_empty()).map(Value::String)),
    ]);
    if !has_context && meta.is_empty() {
        return Ok(None);
    }
    if has_context {
        let ctx = super::message_text::metadata_fields([
            ("summary", args.task.as_ref().map(|s| Value::String(s.clone()))),
            (
                "files",
                args.files.as_ref().map(|f| {
                    Value::Array(f.split(',').map(|s| Value::String(s.trim().to_owned())).collect())
                }),
            ),
            ("branch", args.branch.as_ref().map(|s| Value::String(s.clone()))),
        ]);
        meta.insert("task_context".to_owned(), serde_json::to_value(ctx)?);
    }
    Ok(Some(meta))
}
