// `hiboss boss keys [--pin]` and `hiboss boss trust <text>`: inspect and pin boss signing keys.
// Exports run_keys, run_trust and pin_directory (also used after setup approval).
// Dependencies: client::boss_keys directory, boss_pins store, boss_key_text codec, colored.

use crate::boss_key_text::{self, BossKeyText};
use crate::boss_pins::{self, fingerprint, BossPins, PinnedKey};
use crate::client::boss_keys::{BossKeysResponse, DirectoryBoss};
use crate::client::HiBossClient;
use colored::Colorize;
use std::error::Error;

/// Only native app keys are pinned automatically; the web console's code comes from the server.
const AUTO_PIN_KINDS: [&str; 2] = ["ios", "macos"];

pub async fn run_keys(pin: bool, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let directory = client.get_boss_keys().await?;
    if pin {
        for line in pin_directory(&directory, "first_use")? {
            println!("{line}");
        }
    }
    for boss in &directory.bosses {
        print_boss(boss, boss_pins::load(&boss.boss_id).as_ref());
    }
    Ok(())
}

pub fn run_trust(text: &str) -> Result<(), Box<dyn Error>> {
    let key = boss_key_text::parse(text)?;
    let mut pins = boss_pins::load(&key.boss_id).unwrap_or_else(|| BossPins::new(&key.boss_id, None));
    let fresh = pins.pin(pinned(&key, "manual"));
    let path = boss_pins::save(&pins)?;
    let verb = if fresh { "Pinned" } else { "Already pinned" };
    println!("{verb} {} key {} for boss {} ({})", key.client_kind, fingerprint(&key.key_id), key.boss_id,
        path.display());
    Ok(())
}

/// Pins every unrevoked iOS/macOS key of every boss and records revocations; returns a line per change.
pub fn pin_directory(directory: &BossKeysResponse, via: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let mut lines = Vec::new();
    for boss in &directory.bosses {
        let mut pins = boss_pins::load(&boss.boss_id).unwrap_or_else(|| BossPins::new(&boss.boss_id, None));
        pins.name = Some(boss.name.clone());
        for key in &boss.keys {
            if let Some(revoked_at) = &key.revoked_at {
                pins.revoke(&key.key_id, revoked_at, Some(key.public_key.clone()));
                continue;
            }
            if !AUTO_PIN_KINDS.contains(&key.client_kind.as_str()) {
                continue;
            }
            let text = BossKeyText { boss_id: boss.boss_id.clone(), key_id: key.key_id.clone(),
                public_key: key.public_key.clone(), client_kind: key.client_kind.clone(), label: key.label.clone() };
            // The same checks as `trust`: the id must be the hash of a P-256 key.
            let checked = boss_key_text::parse(&boss_key_text::render(&text))?;
            if pins.pin(pinned(&checked, via)) {
                lines.push(format!("Pinned {} key {} of {} — compare it with Settings › Signing key in the app",
                    key.client_kind, fingerprint(&key.key_id).bold(), boss.name));
            }
        }
        boss_pins::save(&pins)?;
    }
    Ok(lines)
}

fn pinned(key: &BossKeyText, via: &str) -> PinnedKey {
    PinnedKey {
        key_id: key.key_id.clone(), public_key: key.public_key.clone(), client_kind: key.client_kind.clone(),
        label: key.label.clone(), via: via.to_owned(), pinned_at: now(),
    }
}

fn print_boss(boss: &DirectoryBoss, pins: Option<&BossPins>) {
    println!("{} ({})", boss.name.bold(), boss.boss_id);
    if boss.keys.is_empty() {
        println!("  no signing key: this boss's messages are unsigned");
    }
    for key in &boss.keys {
        let state = match pins {
            _ if key.revoked_at.is_some() => "revoked".red(),
            Some(pins) if pins.keys.iter().any(|pinned| pinned.key_id == key.key_id) => "pinned".green(),
            _ => "not pinned".yellow(),
        };
        println!("  {} {:<6} {:<24} {}", fingerprint(&key.key_id), key.client_kind,
            key.label.as_deref().unwrap_or("-"), state);
    }
}

fn now() -> String {
    time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339).unwrap_or_default()
}
