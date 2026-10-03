// Keeps a pending join request on disk so approval survives the setup process.
// Exports Pending with load/save/remove beside config.json; the file holds a poll token, never keys.
// Dependencies: config path and owner-only atomic writer, serde_json, time for created_at.

use super::{api::RequestedProfile, selection::Plan};
use crate::config;
use serde::{Deserialize, Serialize};
use std::{error::Error, fs, io::ErrorKind, path::PathBuf};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

const FILE: &str = "pending-enrollment.json";

#[derive(Serialize, Deserialize)]
pub(super) struct Pending {
    pub server: String,
    pub request_id: String,
    pub poll_token: String,
    pub verification_code: Option<String>,
    pub label: String,
    pub host: String,
    pub profiles: Vec<RequestedProfile>,
    pub created_at: String,
}

impl Pending {
    pub fn new(plan: &Plan, request_id: &str, poll_token: &str, code: Option<&str>) -> Self {
        Self {
            server: plan.server.clone(),
            request_id: request_id.to_owned(),
            poll_token: poll_token.to_owned(),
            verification_code: code.map(str::to_owned),
            label: plan.label.clone(),
            host: plan.host.clone(),
            profiles: plan.profiles.clone(),
            created_at: OffsetDateTime::now_utc()
                .format(&Rfc3339)
                .unwrap_or_default(),
        }
    }

    /// Rebuilds the original plan; the device proof is re-derived from the current config.
    pub fn plan(&self, proof: Option<String>) -> Plan {
        Plan {
            server: self.server.clone(),
            label: self.label.clone(),
            host: self.host.clone(),
            profiles: self.profiles.clone(),
            proof,
        }
    }

    pub fn save(&self) -> Result<(), Box<dyn Error>> {
        config::write_private(&path(), serde_json::to_string_pretty(self)?.as_bytes())
    }
}

pub(super) fn path() -> PathBuf {
    config::config_path().with_file_name(FILE)
}

pub(super) fn load() -> Result<Option<Pending>, Box<dyn Error>> {
    let path = path();
    let body = match fs::read_to_string(&path) {
        Ok(body) => body,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(format!("Cannot read {}", path.display()).into()),
    };
    serde_json::from_str(&body).map(Some).map_err(|_| {
        format!(
            "{} is unreadable; run hiboss setup --abandon to discard it",
            path.display()
        )
        .into()
    })
}

/// Returns whether a file was removed.
pub(super) fn remove() -> Result<bool, Box<dyn Error>> {
    match fs::remove_file(path()) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
        Err(error) => Err(format!("Cannot remove the pending request file: {error}").into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn plan_round_trips_without_a_device_proof() {
        let plan = Plan {
            server: "https://hiboss.example".into(),
            label: "laptop".into(),
            host: "laptop.local".into(),
            profiles: vec![RequestedProfile {
                profile: "aid".into(),
                name: "user-aid@laptop".into(),
            }],
            proof: Some("synthetic-proof".into()),
        };
        let pending = Pending::new(&plan, "request", "token", Some("123456"));
        let body = serde_json::to_string(&pending).unwrap_or_default();
        assert!(!body.contains("synthetic-proof") && body.contains("token"));
        let rebuilt = pending.plan(None);
        assert_eq!(rebuilt.server, plan.server);
        assert_eq!(rebuilt.profiles[0].name, "user-aid@laptop");
        assert!(rebuilt.proof.is_none() && !pending.created_at.is_empty());
    }
}
