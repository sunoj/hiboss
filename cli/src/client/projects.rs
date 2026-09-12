// Purpose: Project profile lookup and explicit alias management HTTP methods.
// Exports: HiBossClient project_profile and change_project_alias.
// Dependencies: reqwest URL paths, serde_json, existing response handling.
use super::HiBossClient;
use crate::team::ProgressTeamFull;
use std::error::Error;

impl HiBossClient {
    pub async fn project_profile(&self, project: &str) -> Result<ProgressTeamFull, Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/progress/teams/", self.base_url))?;
        url.path_segments_mut().map_err(|_| "invalid server URL")?.pop_if_empty().push(project);
        let response = self.http.get(url).bearer_auth(&self.api_key).send().await?;
        Self::parse_response(response).await
    }

    pub async fn change_project_alias(&self, project: &str, alias: &str, remove: bool) -> Result<(), Box<dyn Error>> {
        let mut url = reqwest::Url::parse(&format!("{}/api/projects/", self.base_url))?;
        url.path_segments_mut().map_err(|_| "invalid server URL")?.pop_if_empty().push(project).push("aliases");
        let request = if remove {
            url.path_segments_mut().map_err(|_| "invalid server URL")?.push(alias);
            self.http.delete(url)
        } else {
            self.http.post(url).json(&serde_json::json!({ "alias": alias }))
        };
        let response = request.bearer_auth(&self.api_key).send().await?;
        if !response.status().is_success() {
            return Err(format!("project alias failed ({}): {}", response.status(), response.text().await?).into());
        }
        Ok(())
    }
}
