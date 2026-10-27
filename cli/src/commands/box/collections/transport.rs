// Purpose: Authenticated collection mutation transport for Box commands.
// Extends the Box client with escaped paths and its existing error handling.
use crate::client::HiBossClient;
use reqwest::Method;
use serde_json::Value;
use std::error::Error;

impl HiBossClient {
    pub(crate) async fn mutate_box_collection(
        &self,
        method: Method,
        suffix: &[&str],
        body: Option<Value>,
    ) -> Result<Value, Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/box/collections", self.base_url))?;
        url.path_segments_mut()
            .map_err(|_| "invalid server URL")?
            .extend(suffix);
        let mut request = self.http.request(method, url).bearer_auth(&self.api_key);
        if let Some(body) = body {
            request = request.json(&body);
        }
        self.box_json(request).await
    }
}
