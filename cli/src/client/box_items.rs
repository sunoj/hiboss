// Purpose: Authenticated Box JSON, multipart, pagination and private media transport.
// Exports: HiBossClient Box methods; uses the existing HTTP client and error parser.
// Dependencies: box_types, reqwest, ring, serde, std::path.
use super::HiBossClient;
use crate::box_types::{BoxFilter, BoxItem, BoxMetadata, BoxPage};
use reqwest::{RequestBuilder, Response};
use std::{error::Error, path::Path};

pub(crate) fn fresh_key() -> Result<String, Box<dyn Error>> {
    use ring::rand::{SecureRandom, SystemRandom};
    let mut bytes = [0u8; 16];
    SystemRandom::new()
        .fill(&mut bytes)
        .map_err(|_| "could not generate a Box idempotency key")?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

impl HiBossClient {
    fn box_request(
        &self,
        method: reqwest::Method,
        suffix: &[&str],
    ) -> Result<RequestBuilder, Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/box/items", self.base_url))?;
        url.path_segments_mut()
            .map_err(|_| "invalid server URL")?
            .extend(suffix);
        Ok(self.http.request(method, url).bearer_auth(&self.api_key))
    }

    async fn box_send(&self, request: RequestBuilder) -> Result<Response, Box<dyn Error>> {
        let response = request.send().await.map_err(|err| self.box_error(err))?;
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status();
        let request_id = response
            .headers()
            .get("x-request-id")
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        let body = response.text().await.map_err(|err| self.box_error(err))?;
        let hint = if status == reqwest::StatusCode::NOT_FOUND {
            " (item unavailable or access denied; agents can edit/remove only their own items)"
        } else {
            ""
        };
        Err(self.box_error(super::http_error(
            "Box request failed",
            status,
            request_id,
            body + hint,
        )))
    }

    fn box_error(&self, error: impl std::fmt::Display) -> Box<dyn Error> {
        let message = error.to_string();
        if self.api_key.is_empty() {
            message.into()
        } else {
            message.replace(&self.api_key, "[redacted]").into()
        }
    }

    pub async fn add_box_item(
        &self,
        metadata: &BoxMetadata<'_>,
        file: Option<(&Path, &str)>,
    ) -> Result<BoxItem, Box<dyn Error>> {
        let mut request = self
            .box_request(reqwest::Method::POST, &[])?
            .header("Idempotency-Key", fresh_key()?);
        if let Some((path, mime)) = file {
            let filename = path
                .file_name()
                .ok_or("file has no filename")?
                .to_string_lossy()
                .to_string();
            let bytes =
                std::fs::read(path).map_err(|err| format!("cannot read {}: {err}", path.display()))?;
            let part = reqwest::multipart::Part::bytes(bytes)
                .file_name(filename)
                .mime_str(mime)?;
            let form = reqwest::multipart::Form::new()
                .text("meta", serde_json::to_string(metadata)?)
                .part("file", part);
            request = request.multipart(form);
        } else {
            request = request.json(metadata);
        }
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub async fn latest_box_item(&self, filter: &BoxFilter<'_>) -> Result<BoxItem, Box<dyn Error>> {
        let request = self.box_request(reqwest::Method::GET, &["latest"])?.query(filter);
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub async fn list_box_items(
        &self,
        filter: &BoxFilter<'_>,
        query: Option<&str>,
    ) -> Result<BoxPage, Box<dyn Error>> {
        let suffix: &[&str] = if query.is_some() { &["search"] } else { &[] };
        let mut request = self.box_request(reqwest::Method::GET, suffix)?.query(filter);
        if let Some(query) = query {
            request = request.query(&[("q", query)]);
        }
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub async fn show_box_item(&self, id: &str) -> Result<BoxItem, Box<dyn Error>> {
        let request = self.box_request(reqwest::Method::GET, &[id])?;
        self.box_send(request)
            .await?
            .json()
            .await
            .map_err(|err| self.box_error(err))
    }

    pub async fn box_media(&self, id: &str) -> Result<Response, Box<dyn Error>> {
        let request = self.box_request(reqwest::Method::GET, &[id, "media"])?;
        self.box_send(request).await
    }

    pub async fn remove_box_item(&self, id: &str, purge: bool) -> Result<(), Box<dyn Error>> {
        let mut request = self.box_request(reqwest::Method::DELETE, &[id])?;
        if purge {
            request = request.query(&[("purge", "1")]);
        }
        self.box_send(request).await?;
        Ok(())
    }
}
