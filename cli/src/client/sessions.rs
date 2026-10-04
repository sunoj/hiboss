// Session registration, discovery and heartbeat HTTP methods.
// Exports HiBossClient session methods; depends on reqwest and project resolution.
use super::{HiBossClient, http_error};
use std::error::Error;
use serde_json::Value;

impl HiBossClient {
    pub async fn register_session(
        &self,
        id: &str,
        branch: Option<&str>,
        cwd: Option<&str>,
        label: Option<&str>,
        status: Option<&str>,
        status_text: Option<&str>,
    ) -> Result<(), Box<dyn Error>> {
        let project = crate::session::resolve_project(None);
        let mut body = session_body(id, project);
        let runtime = crate::runtime::RuntimeIdentity::detect();
        let parent = runtime.is_dispatched().then(crate::session::parent_session_id).flatten();
        runtime_fields(&mut body, &runtime, crate::session::short_host(), parent);
        let optional = [
            ("branch", branch),
            ("cwd", cwd),
            ("label", label),
            ("status", status),
            ("status_text", status_text),
        ];
        for (field, value) in optional.into_iter().filter_map(|(field, value)| Some((field, value?))) {
            body[field] = Value::String(value.to_owned());
        }
        let resp = self
            .http
            .post(format!("{}/api/sessions", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let req_id = resp
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let text = resp.text().await.unwrap_or_default();
            return Err(http_error("session register failed", status, req_id, text).into());
        }
        let accepted: Value = resp.json().await.unwrap_or(Value::Null);
        if parent_rejected(&accepted) {
            eprintln!("hiboss: the server rejected the parent session; registered without a parent");
        }
        Ok(())
    }
    pub async fn list_sessions(&self) -> Result<crate::types::SessionsResponse, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/sessions?all=true", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn heartbeat_session(
        &self,
        id: &str,
        status: Option<&str>,
        status_text: Option<&str>,
    ) -> Result<(), Box<dyn Error>> {
        let mut req = self
            .http
            .patch(format!("{}/api/sessions/{}", self.base_url, id))
            .bearer_auth(&self.api_key);
        if status.is_some() || status_text.is_some() {
            let mut body = serde_json::Map::new();
            if let Some(s) = status {
                body.insert("status".into(), serde_json::Value::String(s.to_owned()));
            }
            if let Some(t) = status_text {
                body.insert(
                    "status_text".into(),
                    serde_json::Value::String(t.to_owned()),
                );
            }
            req = req.json(&body);
        }
        let resp = req.send().await?;
        if !resp.status().is_success() { /* ignore heartbeat failures */ }
        Ok(())
    }
    pub async fn mark_all_read(&self) -> Result<u32, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/messages/mark-all-read", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        let data: Value = Self::parse_response(resp).await?;
        Ok(data["marked"].as_u64().unwrap_or(0) as u32)
    }
}

pub(super) fn session_body(id: &str, project: crate::session::ProjectIdentity) -> Value {
    serde_json::json!({ "id": id, "project": project.slug, "project_identity": project })
}

/// Adds `host` (only when the server would accept it), `runtime` and, for a dispatched agent,
/// `dispatch_ref` (its aid task id) and `parent_session_id` when a parent was found.
pub(super) fn runtime_fields(
    body: &mut Value,
    runtime: &crate::runtime::RuntimeIdentity,
    host: Option<String>,
    parent: Option<String>,
) {
    if let Some(host) = host.filter(|host| acceptable_host(host)) {
        body["host"] = Value::String(host);
    }
    body["runtime"] = Value::String(runtime.runtime.clone());
    if runtime.is_dispatched() {
        body["dispatch_ref"] = Value::String(runtime.session_key.clone());
        if let Some(parent) = parent {
            body["parent_session_id"] = Value::String(parent);
        }
    }
}

/// The server refuses the whole registration unless `host` is 1-64 printable ASCII bytes
/// without spaces, so any other host name (spaces, non-ASCII) is left out instead.
fn acceptable_host(host: &str) -> bool {
    (1..=64).contains(&host.len()) && host.bytes().all(|byte| (0x21..=0x7e).contains(&byte))
}

/// True when the server dropped the `parent_session_id` this registration sent.
fn parent_rejected(response: &Value) -> bool {
    response.get("parent_rejected").and_then(Value::as_bool) == Some(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::RuntimeIdentity;

    #[test]
    fn dispatch_ref_and_parent_are_sent_only_for_aid() {
        let aid = RuntimeIdentity { runtime: "aid".into(), session_key: "task-9".into() };
        let mut body = serde_json::json!({});
        runtime_fields(&mut body, &aid, Some("mac".into()), None);
        assert_eq!(body, serde_json::json!({"host": "mac", "runtime": "aid", "dispatch_ref": "task-9"}));
        let mut body = serde_json::json!({});
        runtime_fields(&mut body, &aid, None, Some("sess-p".into()));
        let expected = serde_json::json!({"runtime": "aid", "dispatch_ref": "task-9", "parent_session_id": "sess-p"});
        assert_eq!(body, expected);
        let claude = RuntimeIdentity { runtime: "claude".into(), session_key: "s".into() };
        let mut body = serde_json::json!({});
        runtime_fields(&mut body, &claude, None, Some("sess-p".into()));
        assert_eq!(body, serde_json::json!({"runtime": "claude"}));
    }

    #[test]
    fn host_is_omitted_unless_printable_ascii_without_spaces() {
        let claude = RuntimeIdentity { runtime: "claude".into(), session_key: "s".into() };
        let host = |name: &str| {
            let mut body = serde_json::json!({});
            runtime_fields(&mut body, &claude, Some(name.to_owned()), None);
            body.get("host").cloned()
        };
        assert_eq!(host("mac-mini_2"), Some(Value::String("mac-mini_2".into())));
        assert_eq!(host(&"h".repeat(64)), Some(Value::String("h".repeat(64))));
        let long = "h".repeat(65);
        for rejected in ["", "Ming's Mac mini", "m\u{e9}lanie", "tab\there", "del\u{7f}", long.as_str()] {
            assert_eq!(host(rejected), None, "{rejected:?}");
        }
    }

    #[test]
    fn only_an_explicit_true_is_a_parent_rejection() {
        assert!(parent_rejected(&serde_json::json!({"ok": true, "parent_rejected": true})));
        for response in [serde_json::json!({"ok": true}), serde_json::json!({"parent_rejected": "true"}), Value::Null] {
            assert!(!parent_rejected(&response), "{response}");
        }
    }
}
