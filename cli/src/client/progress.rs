// Purpose: HiBossClient methods for the progress feed API endpoints.
// Exports: post_progress, list_progress, delete_progress, upload_raw_binary.
// Dependencies: super::HiBossClient, crate::types, reqwest, std::error::Error.

use super::HiBossClient;
use reqwest::Method;
use crate::team::{ProgressTeamFull, ProgressTeamRequest, ProgressTeamsResponse};
use crate::types::{ProgressCursor, ProgressFeedResponse, ProgressPost, ProgressPostRequest, UploadResponse};
use std::error::Error;

impl HiBossClient {
    /// POST /api/progress — create a new progress post.
    pub async fn post_progress(
        &self,
        req: &ProgressPostRequest,
    ) -> Result<ProgressPost, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::POST, "/api/progress")
                .json(req)
        ).await
    }

    /// GET /api/progress — list progress posts with optional filters.
    pub async fn list_progress(
        &self,
        project: Option<&str>,
        limit: Option<u32>,
        before: Option<&ProgressCursor>,
    ) -> Result<ProgressFeedResponse, Box<dyn Error>> {
        let mut req = self.request(Method::GET, "/api/progress");
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
        Self::send_json(req).await
    }

    /// DELETE /api/progress/:id — delete a progress post by ID.
    pub async fn delete_progress(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.request(Method::DELETE, &format!("/api/progress/{}", id))
            .send()
            .await?;
        Self::checked_response(resp, "delete progress failed").await?;
        Ok(())
    }

    /// PUT /api/progress/teams/:project — create or update a team identity.
    pub async fn upsert_progress_team(
        &self,
        project: &str,
        req: &ProgressTeamRequest,
    ) -> Result<ProgressTeamFull, Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/progress/teams/", self.base_url))?;
        url.path_segments_mut().map_err(|_| "invalid server URL")?.pop_if_empty().push(project);
        Self::send_json(self.http.put(url).bearer_auth(&self.api_key).json(req)).await
    }

    /// GET /api/progress/teams — list teams within the caller's visibility scope.
    pub async fn list_progress_teams(&self) -> Result<ProgressTeamsResponse, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/progress/teams")).await
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
        Self::send_json(
            self.request(Method::POST, "/api/attachments/upload")
                .header("content-type", ct)
                .header("x-filename", filename)
                .body(data)
        ).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::test_http::{Http, Response};
    use serde_json::{Value, json};

    // Old servers reject object-valued project fields and ignore unknown metadata.
    #[derive(serde::Deserialize)]
    struct OldServerProject {
        project: String,
    }

    #[test]
    fn progress_wire_is_accepted_by_the_old_server_fixture() {
        let identity = crate::session::ProjectIdentity { slug: "repo".into(), aliases: vec!["checkout".into()] };
        let request = ProgressPostRequest {
            body: "progress".into(), project: Some(identity.slug.clone()), project_identity: Some(identity),
            session_id: None, media: None, tags: None, agent_label: None, model: None,
        };
        let body = serde_json::to_value(request).unwrap();
        assert_eq!(body["project_identity"]["aliases"][0], "checkout");
        assert_eq!(serde_json::from_value::<OldServerProject>(body).unwrap().project, "repo");
        assert!(serde_json::from_value::<OldServerProject>(
            serde_json::json!({"project": {"slug": "repo", "aliases": []}})
        ).is_err());
    }

    #[test]
    fn session_wire_is_accepted_by_the_old_server_fixture() {
        let identity = crate::session::ProjectIdentity { slug: "repo".into(), aliases: vec!["checkout".into()] };
        let body = super::super::sessions::session_body("session", identity);
        assert_eq!(body["id"], "session");
        assert_eq!(body["project_identity"]["slug"], "repo");
        assert_eq!(serde_json::from_value::<OldServerProject>(body).unwrap().project, "repo");
    }

    #[tokio::test]
    async fn upload_raw_binary_rejects_missing_file() {
        let client = HiBossClient::new("http://localhost:19999", "test-key");
        let err = client
            .upload_raw_binary("/nonexistent/hiboss-test-progress.mp4", "hiboss-test.mp4")
            .await
            .expect_err("should fail for missing file");
        assert!(err.to_string().contains("file not found"));
    }

    fn serve(body: Value) -> (Http, HiBossClient) {
        let server = Http::start(move |_| Response::json(200, body.clone()));
        let client = HiBossClient::new(&server.url, "test-key");
        (server, client)
    }

    fn request(server: Http, method: &str, path: &str) -> Value {
        let requests = server.requests();
        assert_eq!(requests.len(), 1);
        let request = requests.into_iter().next().unwrap();
        assert_eq!((&*request.method, &*request.path), (method, path));
        assert_eq!(request.header("authorization"), Some("Bearer test-key"));
        request.body
    }

    #[tokio::test]
    async fn list_progress_omits_absent_filters() {
        let (server, client) = serve(json!({"posts": [], "next_cursor": null}));
        let page = client.list_progress(None, None, None).await.unwrap();
        assert!(page.posts.is_empty() && page.next_cursor.is_none());
        assert_eq!(request(server, "GET", "/api/progress"), Value::Null);
    }

    #[tokio::test]
    async fn post_progress_sends_minimal_body_and_decodes_post() {
        let post = json!({"id": "post-1", "project": "repo", "agent_id": "agent-1",
                          "body": "test body", "created_at": "2026-10-28T00:00:00Z"});
        let (server, client) = serve(post);
        let req = ProgressPostRequest {
            body: "test body".into(),
            project: None,
            project_identity: None,
            session_id: None,
            media: None,
            tags: None,
            agent_label: None,
            model: None,
        };
        let result = client.post_progress(&req).await.unwrap();
        assert_eq!((result.id.as_str(), result.body.as_str()), ("post-1", "test body"));
        assert_eq!(request(server, "POST", "/api/progress"), json!({"body": "test body"}));
    }

    #[tokio::test]
    async fn delete_progress_checks_status_and_preserves_typed_errors() {
        for status in [200, 204, 400, 503] {
            let server = Http::start(move |_| Response::json(status, json!("rejected")));
            let client = HiBossClient::new(&server.url, "test-key");
            let result = client.delete_progress("some-id").await;
            match status {
                200 | 204 => assert!(result.is_ok()),
                _ => {
                    let error = result.unwrap_err();
                    let error = error.downcast_ref::<super::super::HttpError>().unwrap();
                    assert_eq!(error.status.as_u16(), status);
                    assert_eq!((error.prefix, error.body.as_str()), ("delete progress failed", "rejected"));
                    assert_eq!(error.request_id, None);
                }
            }
            assert_eq!(request(server, "DELETE", "/api/progress/some-id"), Value::Null);
        }
    }

    #[tokio::test]
    async fn upsert_progress_team_sends_profile_and_decodes_team() {
        let team = json!({"project": "my-project", "display_name": "My Team", "handle": "my-team"});
        let (server, client) = serve(team);
        let req = ProgressTeamRequest {
            display_name: Some("My Team".into()), handle: Some("my-team".into()),
            bio: None, avatar_url: None,
        };
        assert_eq!(client.upsert_progress_team("my-project", &req).await.unwrap().handle, "my-team");
        assert_eq!(request(server, "PUT", "/api/progress/teams/my-project"),
                   json!({"display_name": "My Team", "handle": "my-team"}));
    }

    #[tokio::test]
    async fn list_progress_teams_decodes_visible_teams() {
        let (server, client) = serve(json!({"teams": [{"project": "repo", "display_name": "Team",
                                                     "handle": "team"}]}));
        let teams = client.list_progress_teams().await.unwrap().teams;
        assert_eq!(teams.len(), 1);
        assert_eq!(teams[0].project, "repo");
        assert_eq!(request(server, "GET", "/api/progress/teams"), Value::Null);
    }

    #[tokio::test]
    async fn upsert_progress_team_encodes_project_as_one_segment() {
        // The project must remain one encoded path segment, including reserved characters.
        for (project, path) in [("hiboss", "hiboss"), ("team/a ?#", "team%2Fa%20%3F%23")] {
            let team = json!({"project": project, "display_name": "Team", "handle": "team"});
            let (server, client) = serve(team);
            let result = client.upsert_progress_team(project, &ProgressTeamRequest::default()).await.unwrap();
            assert_eq!(result.project, project);
            assert_eq!(request(server, "PUT", &format!("/api/progress/teams/{path}")), json!({}));
        }
    }
}
