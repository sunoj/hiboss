// Purpose: Define shared stream relay errors and live-lease interpretation.
// Exports: RelayFailure, relay_error, and live_epoch for panel transports.
// Dependencies: serde_json and the time crate.

use serde_json::Value;
use std::error::Error;

#[derive(Debug)]
pub(crate) struct RelayFailure { pub(crate) code: String }
impl std::fmt::Display for RelayFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(formatter, "{}", relay_error(Some(&self.code))) }
}
impl Error for RelayFailure {}

pub(crate) fn relay_error(code: Option<&str>) -> String {
    let code = code.unwrap_or("unknown error");
    let action = match code {
        "lease_conflict" => "Read `hiboss panel state <id>` before taking over a lease",
        "fenced_epoch" | "lease_expired" => "Read `hiboss panel state <id>` and claim a current lease",
        "revision_conflict" => "Read `hiboss panel show <id> --json` and retry with the current revision",
        "unsupported_protocol" => "Upgrade the server and CLI together to protocol v2",
        _ => "Inspect the relay error and correct the request before retrying",
    };
    format!("panel relay stopped: {code}. Next action: {action}")
}

pub(crate) fn live_epoch(state: &Value) -> Option<String> {
    let expires = state.get("leaseExpiresAt").and_then(Value::as_str)?;
    let expires_at = time::OffsetDateTime::parse(expires, &time::format_description::well_known::Rfc3339).ok()?.unix_timestamp();
    (expires_at > time::OffsetDateTime::now_utc().unix_timestamp()).then(|| state.get("epoch").and_then(Value::as_str).map(str::to_owned)).flatten()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relay_error_includes_next_action() { assert!(relay_error(Some("lease_conflict")).contains("panel state")); }

    #[test]
    fn live_epoch_requires_future_expiry() { assert_eq!(live_epoch(&serde_json::json!({"epoch":"old","leaseExpiresAt":"2000-01-01T00:00:00Z"})), None); }
}
