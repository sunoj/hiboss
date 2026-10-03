// Purpose: Diagnose panel authentication, recipients, and relay readiness.
// Exports: run_doctor; boss candidates and defaults come from the server.
// Dependencies: client, session, serde, and panel transport.
use super::transport;
use crate::client::HiBossClient;
use serde::Deserialize;
use serde_json::Value;
use std::error::Error;

#[derive(Debug, Deserialize)]
struct Boss {
    id: String,
    name: String,
    role: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResolvedBosses {
    bosses: Vec<Boss>,
    default_boss_id: Option<String>,
}

pub(super) async fn run_doctor(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let session_id = crate::session::read_session_id().ok_or("No resolved session; run `hiboss hook session-start` and retry")?;
    let sessions = client.list_sessions().await?;
    if !sessions.sessions.iter().any(|session| session.id == session_id) { return Err(format!("session {session_id} is not visible; run `hiboss hook session-start` to refresh it").into()); }
    let bosses = resolved_bosses(&client.list_agent_bosses().await?)?;
    let boss_status = format_boss_status(&bosses);
    let panels = client.list_panels(None).await?;
    let items = panels.get("panels").and_then(Value::as_array).or_else(|| panels.as_array());
    let Some(items) = items else { return Err("panel list response has no panels".into()); };
    let Some(panel) = items.iter().find(|panel| panel.get("sessionId").and_then(Value::as_str) == Some(session_id.as_str())).or_else(|| items.first()) else {
        println!("auth: ok\nprotocol: v2\nsession: {session_id}\n{boss_status}\nrelay: not checked (no panel yet)");
        return Ok(());
    };
    let panel_id = panel.get("panelId").and_then(Value::as_str).ok_or("panel list returned no panelId")?;
    let details = client.get_panel(panel_id).await?;
    if !panel_matches_bosses(details.get("targetBossId").and_then(Value::as_str), &bosses.bosses) { return Err("panel target does not match any resolved agent boss".into()); }
    let ticket = client.issue_panel_connection_ticket(panel_id).await?;
    if !supports_lease_release(&ticket.operations) { return Err("server relay does not support lease.release; deploy the worker before installing this CLI".into()); }
    transport::subscribe(client, panel_id, &ticket).await?;
    println!("auth: ok\nprotocol: v2 (lease.release)\nsession: {session_id}\n{boss_status}\nrelay: ticket and subscribe ok");
    Ok(())
}

fn supports_lease_release(operations: &[String]) -> bool { operations.iter().any(|operation| operation == "lease.release") }

fn resolved_bosses(value: &Value) -> Result<ResolvedBosses, Box<dyn Error>> {
    let resolved: ResolvedBosses = serde_json::from_value(value.clone())
        .map_err(|error| format!("Invalid boss API response: {error}"))?;
    if resolved.bosses.is_empty() {
        return Err("No boss is resolved for this agent; grant access to one boss and retry".into());
    }
    if resolved.default_boss_id.as_deref().is_some_and(|id| !panel_matches_bosses(Some(id), &resolved.bosses)) {
        return Err("boss API defaultBossId does not match a resolved boss".into());
    }
    Ok(resolved)
}

fn format_boss_status(resolved: &ResolvedBosses) -> String {
    let labels: Vec<String> = resolved.bosses.iter()
        .map(|boss| format!("{} ({}) {}", boss.name, boss.role, boss.id)).collect();
    if let [boss] = labels.as_slice() { return format!("boss: {boss}"); }
    let candidates = labels.join(", ");
    if let Some(index) = resolved.bosses.iter().position(|boss| Some(&boss.id) == resolved.default_boss_id.as_ref()) {
        return format!("boss: {} (default publication target)\nbosses: {candidates}", labels[index]);
    }
    format!("boss: {} resolved, no default; set targetBossId to one of: {candidates}", labels.len())
}

fn panel_matches_bosses(target_boss_id: Option<&str>, bosses: &[Boss]) -> bool {
    target_boss_id.is_some_and(|target| bosses.iter().any(|boss| boss.id == target))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const ADMIN_ID: &str = "a9e07edb0d91ff576137fe6fada7b40d";
    const MANAGER_ID: &str = "409a55a0123456789012345678901234";

    #[test]
    fn formats_one_boss_with_full_identity() {
        let bosses = resolved_bosses(&json!({"bosses": [
            {"id": ADMIN_ID, "name": "Ming", "role": "admin"}
        ], "defaultBossId": ADMIN_ID})).expect("bosses");
        assert_eq!(format_boss_status(&bosses), format!("boss: Ming (admin) {ADMIN_ID}"));
    }

    #[test]
    fn formats_server_default_and_all_candidates_with_full_ids() {
        let bosses = resolved_bosses(&json!({"bosses": [
            {"id": ADMIN_ID, "name": "Ming", "role": "admin"},
            {"id": MANAGER_ID, "name": "HiBoss Island", "role": "manager"}
        ], "defaultBossId": ADMIN_ID})).expect("bosses");
        assert_eq!(format_boss_status(&bosses), format!(
            "boss: Ming (admin) {ADMIN_ID} (default publication target)\nbosses: Ming (admin) {ADMIN_ID}, HiBoss Island (manager) {MANAGER_ID}"
        ));
    }

    #[test]
    fn formats_multiple_admins_without_a_default() {
        let bosses = resolved_bosses(&json!({"bosses": [
            {"id": ADMIN_ID, "name": "Ming", "role": "admin"},
            {"id": "other", "name": "Other", "role": "admin"}
        ], "defaultBossId": null})).expect("bosses");
        assert_eq!(format_boss_status(&bosses), format!(
            "boss: 2 resolved, no default; set targetBossId to one of: Ming (admin) {ADMIN_ID}, Other (admin) other"
        ));
    }

    #[test]
    fn never_derives_a_missing_or_null_default_client_side() {
        let value = json!({"bosses": [
            {"id": ADMIN_ID, "name": "Ming", "role": "admin"},
            {"id": MANAGER_ID, "name": "HiBoss Island", "role": "manager"}
        ]});
        for explicit_null in [false, true] {
            let mut response = value.clone();
            if explicit_null { response["defaultBossId"] = Value::Null; }
            let bosses = resolved_bosses(&response).expect("bosses");
            assert!(bosses.default_boss_id.is_none());
            assert!(format_boss_status(&bosses).starts_with("boss: 2 resolved, no default;"));
        }
    }

    #[test]
    fn rejects_empty_malformed_and_inconsistent_responses() {
        for value in [json!({}), json!({"bosses": []}), json!({"bosses": [{"id": "a"}]}),
            json!({"bosses": [{"id": "a", "name": "Ming", "role": "admin"}], "defaultBossId": 12}),
            json!({"bosses": [{"id": "a", "name": "Ming", "role": "admin"}], "defaultBossId": "missing"})] {
            assert!(resolved_bosses(&value).is_err());
        }
    }

    #[test]
    fn panel_target_matches_any_resolved_boss() {
        let bosses = resolved_bosses(&json!({"bosses": [
            {"id": "a", "name": "Ming", "role": "admin"},
            {"id": "b", "name": "Island", "role": "manager"}
        ]})).expect("bosses");
        assert!(panel_matches_bosses(Some("b"), &bosses.bosses));
        assert!(!panel_matches_bosses(Some("c"), &bosses.bosses));
        assert!(!panel_matches_bosses(None, &bosses.bosses));
    }

    #[test]
    fn checks_for_lease_release_capability() {
        assert!(supports_lease_release(&["subscribe".into(), "lease.release".into()]));
        assert!(!supports_lease_release(&["subscribe".into()]));
    }
}
