// Purpose: Implement panel publication and read HTTP calls.
// Exports: PanelPublishResponse and panel methods on HiBossClient.
// Dependencies: reqwest, serde, serde_json, and HiBossClient.

use super::HiBossClient;
use reqwest::Response;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::error::Error;

#[derive(Debug, Deserialize, Serialize)]
pub struct PanelPublishResponse {
    #[serde(rename = "panelId")]
    pub panel_id: String,
    #[serde(rename = "definitionRevision")]
    pub definition_revision: u64,
    #[serde(flatten)]
    pub extra: std::collections::BTreeMap<String, Value>,
}

#[derive(Debug, Deserialize)]
struct ErrorEnvelope { error: PanelError }

#[derive(Debug, Deserialize)]
struct PanelError {
    code: Option<String>,
    message: Option<String>,
    retryable: Option<bool>,
    #[serde(rename = "fieldErrors")]
    field_errors: Option<Value>,
}

impl HiBossClient {
    pub async fn publish_panel(&self, body: &Value, idempotency_key: &str) -> Result<PanelPublishResponse, Box<dyn Error>> {
        let response = self.http.post(format!("{}/api/panels", self.base_url)).bearer_auth(&self.api_key).header("Idempotency-Key", idempotency_key).json(body).send().await?;
        parse_panel_response(response, "panel publication").await
    }

    pub async fn list_panels(&self, cursor: Option<&str>) -> Result<Value, Box<dyn Error>> {
        let mut request = self.http.get(format!("{}/api/panels", self.base_url)).bearer_auth(&self.api_key);
        if let Some(cursor) = cursor { request = request.query(&[("cursor", cursor)]); }
        parse_panel_response(request.send().await?, "panel list").await
    }

    pub async fn get_panel(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let response = self.http.get(format!("{}/api/panels/{}", self.base_url, id)).bearer_auth(&self.api_key).send().await?;
        parse_panel_response(response, "panel lookup").await
    }
}

async fn parse_panel_response<T: serde::de::DeserializeOwned>(response: Response, operation: &str) -> Result<T, Box<dyn Error>> {
    if response.status().is_success() { return Ok(response.json::<T>().await?); }
    let status = response.status();
    let retry_after = response.headers().get("retry-after").and_then(|value| value.to_str().ok()).map(str::to_owned);
    let body = response.text().await.unwrap_or_default();
    Err(format_panel_error(operation, status, retry_after.as_deref(), &body).into())
}

fn format_panel_error(operation: &str, status: reqwest::StatusCode, retry_after: Option<&str>, body: &str) -> String {
    let parsed = serde_json::from_str::<ErrorEnvelope>(body).ok();
    let Some(envelope) = parsed else { return format!("{operation} failed ({status}): {body}"); };
    let error = envelope.error;
    let code = error.code.as_deref().unwrap_or("unknown_error");
    let message = error.message.as_deref().unwrap_or("server rejected the request");
    let path = error_path(error.field_errors.as_ref()).map(|path| format!(" at {path}")).unwrap_or_default();
    let retry = retry_after.map(|value| format!(" Retry after {value}.")).unwrap_or_default();
    format!("{operation} failed ({status}) [{code}]{path}: {message}. {}{}", next_action(code, error.retryable.unwrap_or(false)), retry)
}

fn error_path(field_errors: Option<&Value>) -> Option<String> {
    match field_errors {
        Some(Value::Object(fields)) => fields.keys().next().cloned(),
        Some(Value::Array(fields)) => fields.first().and_then(|field| field.get("path")).and_then(Value::as_str).map(str::to_owned),
        _ => None,
    }
}

fn next_action(code: &str, retryable: bool) -> &'static str {
    match code {
        "invalid_spec" => "Fix the publication document at the reported path and run `hiboss panel validate` again",
        "unsupported_catalog" => "Choose a catalog/version supported by the server",
        "idempotency_conflict" => "Reuse the original file with the original key, or choose a new key for a different publication",
        "rate_limited" => "Wait for the retry interval, then retry the same request with the same key",
        "service_unavailable" => "Retry later; no panel was confirmed by this response",
        _ if retryable => "Retry the request after addressing the transient server condition",
        _ => "Inspect the server message and correct the request before retrying",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_invalid_spec_to_validation_action() { let message = format_panel_error("panel publication", reqwest::StatusCode::UNPROCESSABLE_ENTITY, None, r#"{"error":{"code":"invalid_spec","message":"bad","fieldErrors":{"/spec/root":"missing"}}}"#); assert!(message.contains("at /spec/root") && message.contains("hiboss panel validate")); }

    #[test]
    fn maps_rate_limit_to_retry_action() { let message = format_panel_error("panel publication", reqwest::StatusCode::TOO_MANY_REQUESTS, Some("5"), r#"{"error":{"code":"rate_limited","message":"slow","retryable":true}}"#); assert!(message.contains("Wait for the retry interval") && message.contains("Retry after 5")); }

    #[test]
    fn deserializes_machine_readable_publish_response() { let response: PanelPublishResponse = serde_json::from_str(r#"{"panelId":"panel_1","definitionRevision":1,"metadataVersion":1}"#).expect("response"); assert_eq!((response.panel_id, response.definition_revision), ("panel_1".into(), 1)); }
}
