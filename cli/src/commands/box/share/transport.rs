// Purpose: Authenticated share-link transport for Box items (create, list, revoke).
// Extends the Box client; reuses its path escaping, error parsing and key redaction.
use crate::client::HiBossClient;
use crate::commands::box_cmd::share::{BoxShare, BoxShareList};
use reqwest::Method;
use std::error::Error;

impl HiBossClient {
    pub(crate) async fn create_box_share(
        &self,
        item: &str,
        ttl_seconds: Option<u64>,
    ) -> Result<BoxShare, Box<dyn Error>> {
        let body = match ttl_seconds {
            Some(ttl) => serde_json::json!({ "ttlSeconds": ttl }),
            None => serde_json::json!({}),
        };
        let request = self
            .box_request(Method::POST, &[item, "shares"])?
            .json(&body);
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub(crate) async fn list_box_shares(&self, item: &str) -> Result<BoxShareList, Box<dyn Error>> {
        let request = self.box_request(Method::GET, &[item, "shares"])?;
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub(crate) async fn revoke_box_share(&self, share: &str) -> Result<(), Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/box/shares", self.base_url))?;
        url.path_segments_mut()
            .map_err(|_| "invalid server URL")?
            .push(share);
        self.box_send(self.http.delete(url).bearer_auth(&self.api_key))
            .await?;
        Ok(())
    }
}
