// Purpose: Team identity types for the progress feed v2 API.
// Exports: ProgressTeam, ProgressTeamFull, ProgressTeamRequest, ProgressTeamsResponse.
// Dependencies: serde.

use serde::{Deserialize, Serialize};

/// Embedded team identity included on every progress post.
/// `registered: false` means the server returned a fallback identity; the project
/// has no registered team yet.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProgressTeam {
    pub handle: String,
    pub display_name: String,
    pub avatar_url: String,
    #[serde(default)]
    pub registered: bool,
}

/// Full team record returned by PUT /api/progress/teams/:project and GET /api/progress/teams.
#[derive(Debug, Serialize, Deserialize)]
pub struct ProgressTeamFull {
    pub id: String,
    pub project: String,
    pub handle: String,
    pub display_name: String,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// Request body for PUT /api/progress/teams/:project.
#[derive(Debug, Serialize, Default)]
pub struct ProgressTeamRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
}

/// Response from GET /api/progress/teams.
#[derive(Debug, Deserialize)]
pub struct ProgressTeamsResponse {
    pub teams: Vec<ProgressTeamFull>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn team_request_skips_none_fields() {
        let req = ProgressTeamRequest {
            handle: Some("myteam".into()),
            ..Default::default()
        };
        let json = serde_json::to_value(&req).expect("serialize");
        assert_eq!(json["handle"], "myteam");
        assert!(json.get("bio").is_none(), "None bio must be omitted");
        assert!(json.get("avatar_url").is_none(), "None avatar_url must be omitted");
        assert!(json.get("display_name").is_none(), "None display_name must be omitted");
    }

    #[test]
    fn team_request_all_fields() {
        let req = ProgressTeamRequest {
            handle: Some("h".into()),
            display_name: Some("Name".into()),
            bio: Some("A bio".into()),
            avatar_url: Some("https://example.com/a.jpg".into()),
        };
        let json = serde_json::to_value(&req).expect("serialize");
        assert_eq!(json["handle"], "h");
        assert_eq!(json["display_name"], "Name");
        assert_eq!(json["bio"], "A bio");
        assert_eq!(json["avatar_url"], "https://example.com/a.jpg");
    }

    #[test]
    fn progress_team_registered_defaults_false() {
        let json = r#"{"handle":"x","display_name":"X","avatar_url":"u"}"#;
        let t: ProgressTeam = serde_json::from_str(json).expect("parse");
        assert!(!t.registered);
    }

    #[test]
    fn progress_team_registered_true() {
        let json = r#"{"handle":"x","display_name":"X","avatar_url":"u","registered":true}"#;
        let t: ProgressTeam = serde_json::from_str(json).expect("parse");
        assert!(t.registered);
    }
}
