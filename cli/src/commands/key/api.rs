// Typed HTTP operations for agent credential management.
// Exports KeyApi and wire contracts; depends on reqwest and serde.
use serde::{Deserialize, Serialize};
use std::{error::Error, time::Duration};

#[derive(Deserialize)]
pub struct Identity { pub id: String, pub agent_key_id: Option<String> }
#[derive(Deserialize)]
pub struct Grant { pub id: String, pub key: String }
#[derive(Deserialize, Serialize)]
pub struct Key {
    pub id: String, pub label: String, pub created_at: String,
    pub last_used_at: Option<String>, pub revoked_at: Option<String>,
}
#[derive(Deserialize, Serialize)]
pub struct Inventory { pub keys: Vec<Key>, pub current_key_id: Option<String> }

pub struct KeyApi { http: reqwest::Client, server: String, key: String }
impl KeyApi {
    pub fn new(server: &str, key: &str) -> Self {
        Self { http: reqwest::Client::new(), server: server.trim_end_matches('/').into(), key: key.into() }
    }
    fn request(&self, method: reqwest::Method, path: &str) -> reqwest::RequestBuilder {
        self.http.request(method, format!("{}/api/agents/me{path}", self.server))
            .bearer_auth(&self.key).timeout(Duration::from_secs(30))
    }
    pub async fn me(&self) -> Result<Identity, Box<dyn Error>> {
        Ok(self.request(reqwest::Method::GET, "").send().await?.error_for_status()?.json().await?)
    }
    pub async fn list(&self) -> Result<Inventory, Box<dyn Error>> {
        Ok(self.request(reqwest::Method::GET, "/keys").send().await?.error_for_status()?.json().await?)
    }
    pub async fn mint(&self, label: &str) -> Result<Grant, Box<dyn Error>> {
        Ok(self.request(reqwest::Method::POST, "/keys").json(&serde_json::json!({ "label": label }))
            .send().await?.error_for_status()?.json().await?)
    }
    pub async fn revoke(&self, id: &str) -> Result<(), Box<dyn Error>> {
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
            return Err("invalid key ID".into());
        }
        let response = self.request(reqwest::Method::DELETE, &format!("/keys/{id}")).send().await?;
        if response.status() == reqwest::StatusCode::CONFLICT {
            return Err("cannot revoke the current key when it is the last live key".into());
        }
        response.error_for_status()?;
        Ok(())
    }
}
