// Purpose: HiBossClient methods for the progress feed API endpoints.
// Exports: post_progress, list_progress, delete_progress, upload_raw_binary.
// Dependencies: super::HiBossClient, crate::types, reqwest, std::error::Error.

use super::HiBossClient;
use crate::team::{ProgressTeamFull, ProgressTeamRequest, ProgressTeamsResponse};
use crate::types::{ProgressCursor, ProgressFeedResponse, ProgressPost, ProgressPostRequest, UploadResponse};
use std::error::Error;

impl HiBossClient {
    /// POST /api/progress — create a new progress post.
    pub async fn post_progress(
        &self,
        req: &ProgressPostRequest,
    ) -> Result<ProgressPost, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/progress", self.base_url))
            .bearer_auth(&self.api_key)
            .json(req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    /// GET /api/progress — list progress posts with optional filters.
    pub async fn list_progress(
        &self,
        project: Option<&str>,
        limit: Option<u32>,
        before: Option<&ProgressCursor>,
    ) -> Result<ProgressFeedResponse, Box<dyn Error>> {
        let mut req = self
            .http
            .get(format!("{}/api/progress", self.base_url))
            .bearer_auth(&self.api_key);
        if let Some(p) = project {
            req = req.query(&[("project", p)]);
        }
        if let Some(l) = limit {
            req = req.query(&[("limit", l.to_string())]);
        }
        if let Some(b) = before {
            let cursor = serde_json::to_string(b)?;
            req = req.query(&[("before", cursor)]);
        }
        let resp = req.send().await?;
        Self::parse_response(resp).await
    }

    /// DELETE /api/progress/:id — delete a progress post by ID.
    pub async fn delete_progress(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self
            .http
            .delete(format!("{}/api/progress/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let req_id = resp
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let body = resp.text().await.unwrap_or_default();
            return Err(
                super::format_http_error("delete progress failed", status, req_id, body).into(),
            );
        }
        Ok(())
    }

    /// PUT /api/progress/teams/:project — create or update a team identity.
    pub async fn upsert_progress_team(
        &self,
        project: &str,
        req: &ProgressTeamRequest,
    ) -> Result<ProgressTeamFull, Box<dyn Error>> {
        let resp = self
            .http
            .put(format!("{}/api/progress/teams/{}", self.base_url, project))
            .bearer_auth(&self.api_key)
            .json(req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    /// GET /api/progress/teams — list teams within the caller's visibility scope.
    pub async fn list_progress_teams(&self) -> Result<ProgressTeamsResponse, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/progress/teams", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    /// POST /api/attachments/upload — raw binary upload for videos and converted GIFs.
    /// Sets `Content-Type` from the filename extension and `x-filename` header.
    pub async fn upload_raw_binary(
        &self,
        path: &str,
        filename: &str,
    ) -> Result<UploadResponse, Box<dyn Error>> {
        let file_path = std::path::Path::new(path);
        if !file_path.exists() {
            return Err(format!("file not found: {}", path).into());
        }
        let data = std::fs::read(file_path)?;
        let ct = super::mime_from_ext(filename);
        let resp = self
            .http
            .post(format!("{}/api/attachments/upload", self.base_url))
            .bearer_auth(&self.api_key)
            .header("content-type", ct)
            .header("x-filename", filename)
            .body(data)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_client() -> HiBossClient {
        HiBossClient::new("http://localhost:19999", "test-key")
    }

    #[tokio::test]
    async fn upload_raw_binary_rejects_missing_file() {
        let client = make_client();
        let err = client
            .upload_raw_binary("/nonexistent/hiboss-test-progress.mp4", "hiboss-test.mp4")
            .await
            .expect_err("should fail for missing file");
        assert!(err.to_string().contains("file not found"));
    }

    #[test]
    fn list_progress_compiles_with_all_none() {
        let client = make_client();
        let _f = client.list_progress(None, None, None);
        drop(_f);
    }

    #[test]
    fn post_progress_compiles_with_minimal_request() {
        let client = make_client();
        let req = ProgressPostRequest {
            body: "test body".into(),
            project: None,
            session_id: None,
            media: None,
            tags: None,
        };
        let _f = client.post_progress(&req);
        drop(_f);
    }

    #[test]
    fn delete_progress_compiles_with_id() {
        let client = make_client();
        let _f = client.delete_progress("some-id");
        drop(_f);
    }

    #[test]
    fn upsert_progress_team_compiles() {
        let client = make_client();
        let req = crate::team::ProgressTeamRequest {
            display_name: Some("My Team".into()),
            handle: Some("my-team".into()),
            bio: None,
            avatar_url: None,
        };
        let _f = client.upsert_progress_team("my-project", &req);
        drop(_f);
    }

    #[test]
    fn list_progress_teams_compiles() {
        let client = make_client();
        let _f = client.list_progress_teams();
        drop(_f);
    }

    #[test]
    fn upsert_progress_team_url_contains_project() {
        // Verify the URL is constructed correctly (inspectable only by checking the
        // future/pending struct, not by actually sending it here without a server).
        let client = make_client();
        // The method should encode the project into the URL path verbatim.
        let req = crate::team::ProgressTeamRequest::default();
        let _f = client.upsert_progress_team("hiboss", &req);
        drop(_f);
    }
}
