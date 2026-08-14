// Purpose: Detect agent label and model for progress post attribution.
// Exports: Attribution, detect.
// Dependencies: std::env, std::fs, std::io, std::path, serde, serde_json.

use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

/// Maximum bytes to read from the tail of a transcript file.
const MAX_TAIL_BYTES: u64 = 512 * 1024;
const MAX_ATTR_LEN: usize = 64;

/// Attribution inferred from the current environment.
pub struct Attribution {
    pub agent_label: Option<String>,
    pub model: Option<String>,
}

/// Detect agent label and model from the environment. Never panics.
/// Any failure yields None for the affected field; the caller proceeds
/// without attribution. Detection is best-effort and adds no network I/O.
pub fn detect() -> Attribution {
    Attribution {
        agent_label: detect_agent_label(),
        model: detect_model(),
    }
}

fn detect_agent_label() -> Option<String> {
    // Claude Code sets both CLAUDECODE=1 and CLAUDE_CODE_ENTRYPOINT.
    if std::env::var("CLAUDECODE").as_deref() == Ok("1")
        && std::env::var("CLAUDE_CODE_ENTRYPOINT").is_ok()
    {
        return Some("claude-code".to_owned());
    }
    None
}

/// Detect the model from the Claude Code session transcript.
/// Only attempts detection when CLAUDE_CODE_SESSION_ID is set.
fn detect_model() -> Option<String> {
    let session_id = std::env::var("CLAUDE_CODE_SESSION_ID").ok()?;
    let home = std::env::var("HOME").ok()?;
    let path = find_transcript_path(&home, &session_id)?;
    read_model_from_transcript(&path)
}

/// Search $HOME/.claude/projects/ for a JSONL file matching the session ID.
/// Returns the first match; session IDs are UUIDs so collisions are negligible.
fn find_transcript_path(home: &str, session_id: &str) -> Option<PathBuf> {
    let target = format!("{session_id}.jsonl");
    let projects_dir = PathBuf::from(home).join(".claude").join("projects");
    for entry in fs::read_dir(&projects_dir).ok()?.flatten() {
        let candidate = entry.path().join(&target);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Read the model from the last `"type":"assistant"` record in a JSONL transcript.
/// Reads at most MAX_TAIL_BYTES from the file end; the last assistant record is
/// always near the end of the file, so this avoids reading large early history.
pub(crate) fn read_model_from_transcript(path: &Path) -> Option<String> {
    let mut file = fs::File::open(path).ok()?;
    let file_len = file.metadata().ok()?.len();
    if file_len == 0 {
        return None;
    }
    let tail_start = file_len.saturating_sub(MAX_TAIL_BYTES);
    file.seek(SeekFrom::Start(tail_start)).ok()?;
    let read_len = (file_len - tail_start) as usize;
    let mut buf = vec![0u8; read_len];
    file.read_exact(&mut buf).ok()?;
    // Use lossy UTF-8 so a partial first line (if tail_start > 0) cannot abort parsing.
    let text = String::from_utf8_lossy(&buf);
    // Scan from the last line backwards; the last assistant record wins.
    for line in text.lines().rev() {
        if let Some(model) = extract_model_from_line(line) {
            return Some(model);
        }
    }
    None
}

// Minimal structs for parsing only the fields we need from a transcript line.
#[derive(serde::Deserialize)]
struct AssistantRecord {
    #[serde(rename = "type")]
    rec_type: String,
    message: Option<AssistantMessage>,
}

#[derive(serde::Deserialize)]
struct AssistantMessage {
    model: Option<String>,
}

/// Extract the model string from a single JSONL line. Returns None on any error,
/// missing field, wrong record type, or value exceeding MAX_ATTR_LEN.
fn extract_model_from_line(line: &str) -> Option<String> {
    let rec: AssistantRecord = serde_json::from_str(line).ok()?;
    if rec.rec_type != "assistant" {
        return None;
    }
    let model = rec.message?.model?;
    if model.is_empty() || model.len() > MAX_ATTR_LEN {
        return None;
    }
    Some(model)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("hiboss_attr_{name}.jsonl"))
    }

    #[test]
    fn no_transcript_returns_none() {
        let result = read_model_from_transcript(Path::new("/nonexistent/no_such_file.jsonl"));
        assert!(result.is_none());
    }

    #[test]
    fn last_assistant_record_wins() {
        let path = tmp_path("last_wins");
        let lines = [
            r#"{"type":"assistant","message":{"model":"claude-opus-4"}}"#,
            r#"{"type":"user","message":{}}"#,
            r#"{"type":"assistant","message":{"model":"claude-opus-5"}}"#,
        ];
        fs::write(&path, lines.join("\n")).expect("write test fixture");
        let result = read_model_from_transcript(&path);
        assert_eq!(result.as_deref(), Some("claude-opus-5"));
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn malformed_line_is_skipped() {
        let path = tmp_path("malformed");
        let lines = [
            r#"{"type":"assistant","message":{"model":"claude-opus-4"}}"#,
            r#"{not valid json}"#,
            r#"{"type":"assistant","message":{"model":"claude-opus-5"}}"#,
            r#"GARBAGE"#,
        ];
        fs::write(&path, lines.join("\n")).expect("write test fixture");
        let result = read_model_from_transcript(&path);
        assert_eq!(result.as_deref(), Some("claude-opus-5"));
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn no_assistant_records_returns_none() {
        let path = tmp_path("no_assistant");
        let lines = [
            r#"{"type":"user","message":{}}"#,
            r#"{"type":"tool_result","content":[]}"#,
        ];
        fs::write(&path, lines.join("\n")).expect("write test fixture");
        let result = read_model_from_transcript(&path);
        assert!(result.is_none());
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn model_over_max_len_is_rejected() {
        let path = tmp_path("long_model");
        let long = "x".repeat(65);
        let line = format!(r#"{{"type":"assistant","message":{{"model":"{long}"}}}}"#);
        fs::write(&path, line).expect("write test fixture");
        let result = read_model_from_transcript(&path);
        assert!(result.is_none());
        let _ = fs::remove_file(&path);
    }
}
