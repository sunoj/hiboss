// Validates one-time approval credentials and atomically saves all requested profiles.
// Exports persist within onboarding; uses config v2 owner-only atomic storage.
// Existing credentials and default profile are retained before runtime installation.

use super::{
    api::JoinState,
    selection::{Plan, normalize_server},
};
use crate::config::{self, Profile};
use std::{collections::BTreeSet, error::Error};

pub(super) fn persist(plan: &Plan, state: JoinState) -> Result<(), Box<dyn Error>> {
    if state.delivered {
        return Err("Approval keys were already delivered; request setup again".into());
    }
    let device_id = state
        .device_id
        .filter(|id| !id.is_empty())
        .ok_or("Approval is missing device identity")?;
    validate_profiles(plan, &state.profiles)?;
    config::update_saved_config(|config| merge_approval(config, plan, device_id, state.profiles))
}

fn merge_approval(
    config: &mut config::Config,
    plan: &Plan,
    device_id: String,
    profiles: Vec<super::api::ApprovedProfile>,
) -> Result<(), Box<dyn Error>> {
    validate_config(config, plan, &device_id)?;
    for entry in profiles {
        config.profiles.insert(
            entry.profile,
            Profile {
                key: entry.key,
                agent_id: entry.agent_id,
                name: Some(entry.name),
                server: None,
            },
        );
    }
    config.server = Some(plan.server.clone());
    config.device_id = Some(device_id);
    if !config.profiles.contains_key(&config.default_profile) {
        config.default_profile = plan
            .profiles
            .first()
            .ok_or("No requested profile")?
            .profile
            .clone();
    }
    Ok(())
}

fn validate_config(
    config: &config::Config,
    plan: &Plan,
    device_id: &str,
) -> Result<(), Box<dyn Error>> {
    if plan.proof.is_some() && config.device_id.as_deref() != Some(device_id) {
        return Err("Approval changed device identity; existing credentials were preserved".into());
    }
    if config.profiles.keys().any(|name| {
        plan.profiles
            .iter()
            .any(|requested| &requested.profile == name)
    }) {
        return Err("Config changed during approval; existing profiles were preserved".into());
    }
    if let Some(server) = config.server.as_ref() {
        if normalize_server(server)? != plan.server && !config.profiles.is_empty() {
            return Err(
                "Config server changed during approval; existing credentials were preserved".into(),
            );
        }
    }
    Ok(())
}

fn validate_profiles(
    plan: &Plan,
    profiles: &[super::api::ApprovedProfile],
) -> Result<(), Box<dyn Error>> {
    let names: BTreeSet<_> = profiles.iter().map(|entry| &entry.profile).collect();
    if profiles.len() != plan.profiles.len() || names.len() != profiles.len() {
        return Err("Approval does not contain exactly the requested profiles".into());
    }
    for entry in profiles {
        if !plan
            .profiles
            .iter()
            .any(|requested| requested.profile == entry.profile && requested.name == entry.name)
            || entry.key.as_ref().is_none_or(|key| key.is_empty())
            || entry.agent_id.as_ref().is_none_or(|id| id.is_empty())
        {
            return Err(
                "Approval profile credentials are incomplete or do not match the request".into(),
            );
        }
    }
    Ok(())
}
