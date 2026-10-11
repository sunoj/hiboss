// Builds the complete Markdown content and structured context of a send request.
// Exports build_metadata; body content never comes from the private push summary.
// Dependencies: SendArgs, message text loading, and serde_json.

use super::send::SendArgs;
use serde_json::Value;
use std::{collections::HashMap, error::Error};

pub(crate) fn build_metadata(
    args: &SendArgs,
) -> Result<Option<HashMap<String, Value>>, Box<dyn Error>> {
    let content =
        super::message_text::content(args.content.as_deref(), args.content_file.as_deref())?;
    let has_context = args.task.is_some() || args.files.is_some() || args.branch.is_some();
    let has_content = content.as_ref().is_some_and(|s| !s.is_empty());
    if !has_context && args.summary.is_none() && !has_content {
        return Ok(None);
    }
    let mut meta = HashMap::new();
    if let Some(ref s) = args.summary {
        meta.insert("summary".to_owned(), Value::String(s.clone()));
    }
    if let Some(ref s) = content {
        if !s.is_empty() {
            meta.insert("content".to_owned(), Value::String(s.clone()));
        }
    }
    if has_context {
        let mut ctx = HashMap::new();
        if let Some(ref t) = args.task {
            ctx.insert("summary".to_owned(), Value::String(t.clone()));
        }
        if let Some(ref f) = args.files {
            let files: Vec<Value> = f
                .split(',')
                .map(|s| Value::String(s.trim().to_owned()))
                .collect();
            ctx.insert("files".to_owned(), Value::Array(files));
        }
        if let Some(ref b) = args.branch {
            ctx.insert("branch".to_owned(), Value::String(b.clone()));
        }
        meta.insert("task_context".to_owned(), serde_json::to_value(ctx)?);
    }
    Ok(Some(meta))
}
