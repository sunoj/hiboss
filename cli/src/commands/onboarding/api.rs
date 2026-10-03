// Typed machine enrollment API and bounded HTTP transport.
// Exports join/status responses and helpers within onboarding.
// Dependencies: reqwest, serde, and setup arguments; responses never enter diagnostics.

use super::{SetupArgs, selection::Plan};
use reqwest::{Client, RequestBuilder};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{error::Error, time::Duration};

pub(crate) fn http() -> Result<Client, Box<dyn Error>> {
    Ok(Client::builder()
        .timeout(Duration::from_secs(10))
        .redirect(reqwest::redirect::Policy::none())
        .build()?)
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct RequestedProfile {
    pub profile: String,
    pub name: String,
}

#[derive(Deserialize)]
pub(super) struct ApprovedProfile {
    pub profile: String,
    pub name: String,
    pub agent_id: Option<String>,
    pub key: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct JoinResponse {
    pub request_id: String,
    pub poll_token: String,
    #[serde(flatten)]
    pub state: JoinState,
}

#[derive(Deserialize)]
pub(super) struct JoinState {
    pub status: String,
    pub device_id: Option<String>,
    pub verification_code: Option<String>,
    #[serde(default)]
    pub delivered: bool,
    #[serde(default)]
    pub profiles: Vec<ApprovedProfile>,
}

#[derive(Deserialize, Default)]
struct Failure {
    #[serde(default)]
    conflicts: Vec<String>,
}

pub(crate) async fn response<T: DeserializeOwned>(
    request: RequestBuilder,
) -> Result<T, Box<dyn Error>> {
    let (http, request) = request.build_split();
    let request = request.map_err(|_| "Invalid HiBoss request")?;
    let secrets: Vec<String> = ["authorization", "x-device-proof", "x-bootstrap-secret"]
        .into_iter()
        .filter_map(|header| request.headers().get(header)?.to_str().ok())
        .map(|value| value.strip_prefix("Bearer ").unwrap_or(value).to_owned())
        .filter(|value| !value.is_empty())
        .collect();
    let response = http.execute(request).await.map_err(transport_error)?;
    let status = response.status();
    if status.is_success() {
        return response.json().await.map_err(|error| {
            if error.is_timeout() {
                transport_error(error)
            } else {
                "Invalid HiBoss response".into()
            }
        });
    }
    let failure: Failure = match response.json().await {
        Ok(failure) => failure,
        Err(error) if error.is_timeout() => return Err(transport_error(error)),
        Err(_) => Failure::default(),
    };
    let mut message = match status.as_u16() {
        401 => "Authorization failed: check the device proof or bootstrap secret".to_owned(),
        403 => "Invite missing, used or expired; mint another with hiboss device invite".to_owned(),
        409 => format!(
            "Conflicting names: {}. Choose a different --label",
            failure.conflicts.join(", ")
        ),
        429 => "Five invites are already active; wait for one to expire or be used".to_owned(),
        _ => format!("HiBoss request failed ({status})"),
    };
    for secret in secrets {
        message = message.replace(&secret, "[redacted]");
    }
    Err(message.into())
}

fn transport_error(error: reqwest::Error) -> Box<dyn Error> {
    if error.is_timeout() {
        "HiBoss request timeout; run setup again to request approval".into()
    } else {
        "HiBoss request failed; check the server connection".into()
    }
}

pub(super) async fn join(
    http: &Client,
    plan: &Plan,
    args: &SetupArgs,
) -> Result<JoinResponse, Box<dyn Error>> {
    let mut body = serde_json::json!({
        "device": {"label": plan.label, "host": plan.host}, "profiles": plan.profiles
    });
    let mut request = http.post(format!("{}/api/join", plan.server));
    if let Some(key) = &plan.proof {
        request = request.header("X-Device-Proof", key);
    } else if let Some(invite) = &args.invite {
        body["invite"] = serde_json::json!(invite);
    }
    let secret = args
        .bootstrap_secret
        .clone()
        .or_else(|| std::env::var("HIBOSS_BOOTSTRAP_SECRET").ok());
    if let Some(secret) = secret {
        request = request.header("X-Bootstrap-Secret", secret);
    }
    response(request.json(&body)).await
}

pub(super) async fn status(
    http: &Client,
    server: &str,
    token: &str,
) -> Result<JoinState, Box<dyn Error>> {
    response(
        http.get(format!("{server}/api/join/status"))
            .query(&[("token", token)]),
    )
    .await
}
