// Boss public keys pinned on this machine; boss signatures verify against these, not the server's copy.
// Exports BossPins, PinnedKey, PinLookup, lookup, any_pins, load, save, fingerprint, key text codec.
// Files: <dir of the real config.json>/boss-keys/<boss_id>.json, mode 0600 in a 0700 directory.
// Dependencies: serde_json, base64url helpers in this file, std::fs.

use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fs;
use std::path::PathBuf;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct PinnedKey {
    pub key_id: String,
    pub public_key: String,
    pub client_kind: String,
    #[serde(default)]
    pub label: Option<String>,
    /// How the key was trusted: `first_use` (setup), `manual` (`boss trust`), `invite`.
    pub via: String,
    pub pinned_at: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct RevokedKey {
    pub key_id: String,
    pub revoked_at: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct BossPins {
    pub version: u8,
    pub boss_id: String,
    #[serde(default)]
    pub name: Option<String>,
    pub keys: Vec<PinnedKey>,
    #[serde(default)]
    pub revoked: Vec<RevokedKey>,
}

/// What a signature's key id means on this machine.
#[derive(Debug, PartialEq)]
pub enum PinLookup {
    /// Pinned and not revoked: verify with these public-key bytes.
    Pinned(Vec<u8>),
    /// Revoked: no signature by this key verifies, whatever time it claims.
    Revoked,
    Unknown,
}

impl BossPins {
    pub fn new(boss_id: &str, name: Option<String>) -> Self {
        Self { version: 1, boss_id: boss_id.to_owned(), name, keys: Vec::new(), revoked: Vec::new() }
    }

    pub fn is_revoked(&self, key_id: &str) -> bool {
        self.revoked.iter().any(|key| key.key_id == key_id)
    }

    /// Adds a key once; a revoked key is never pinned again.
    pub fn pin(&mut self, key: PinnedKey) -> bool {
        if self.is_revoked(&key.key_id) || self.keys.iter().any(|pinned| pinned.key_id == key.key_id) {
            return false;
        }
        self.keys.push(key);
        true
    }

    pub fn revoke(&mut self, key_id: &str, revoked_at: &str) {
        self.keys.retain(|key| key.key_id != key_id);
        if !self.is_revoked(key_id) {
            self.revoked.push(RevokedKey { key_id: key_id.to_owned(), revoked_at: revoked_at.to_owned() });
        }
    }
}

/// The pins directory sits beside the real config file, like `signing/`.
pub fn pins_dir() -> PathBuf {
    let path = crate::config::config_path();
    let real = fs::canonicalize(&path).unwrap_or(path);
    real.parent().map(|parent| parent.join("boss-keys")).unwrap_or_else(|| PathBuf::from("boss-keys"))
}

/// Every pin file, and whether any `.json` there could not be read: a damaged store still counts
/// as pinned, so it never falls back to trusting the key the server offers.
pub fn load_store() -> (Vec<BossPins>, bool) {
    #[cfg(test)]
    if let Some(pins) = tests_support::override_pins() {
        return (pins, tests_support::damaged());
    }
    let entries = match fs::read_dir(pins_dir()) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return (Vec::new(), false),
        // A pins directory that exists but cannot be listed is damaged, never empty.
        Err(_) => return (Vec::new(), true),
    };
    let mut damaged = false;
    let mut pins = Vec::new();
    for entry in entries {
        let Ok(entry) = entry else { damaged = true; continue };
        if entry.path().extension().is_none_or(|ext| ext != "json") { continue; }
        match fs::read_to_string(entry.path()).ok().and_then(|text| serde_json::from_str::<BossPins>(&text).ok()) {
            Some(file) => pins.push(file),
            None => damaged = true,
        }
    }
    (pins, damaged)
}

pub fn load_all() -> Vec<BossPins> {
    load_store().0
}

pub fn load(boss_id: &str) -> Option<BossPins> {
    load_all().into_iter().find(|pins| pins.boss_id == boss_id)
}

/// True once this machine has pinned any boss key (or its pin store is damaged).
pub fn any_pins() -> bool {
    let (pins, damaged) = load_store();
    damaged || pins.iter().any(|pins| !pins.keys.is_empty() || !pins.revoked.is_empty())
}

pub fn lookup(boss_id: &str, key_id: &str) -> PinLookup {
    let Some(pins) = load(boss_id) else { return PinLookup::Unknown };
    if pins.is_revoked(key_id) {
        return PinLookup::Revoked;
    }
    pins.keys.iter().find(|key| key.key_id == key_id)
        .and_then(|key| decode_b64url(&key.public_key))
        .map_or(PinLookup::Unknown, PinLookup::Pinned)
}

pub fn save(pins: &BossPins) -> Result<PathBuf, Box<dyn Error>> {
    if !is_plain_id(&pins.boss_id) {
        return Err(format!("refusing boss id {:?}", pins.boss_id).into());
    }
    let dir = pins_dir();
    fs::create_dir_all(&dir)?;
    let path = dir.join(format!("{}.json", pins.boss_id));
    // A temp name of its own per writer, created owner-only, then renamed into place.
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let tmp = dir.join(format!(".{}.{}.{nanos}.tmp", pins.boss_id, std::process::id()));
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        options.mode(0o600);
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    }
    std::io::Write::write_all(&mut options.open(&tmp)?, &serde_json::to_vec_pretty(pins)?)?;
    fs::rename(&tmp, &path)?;
    Ok(path)
}

/// `xxxx-xxxx-xxxx-xxxx`: the first 16 characters of the key id, as the apps show it.
pub fn fingerprint(key_id: &str) -> String {
    key_id.chars().take(16).collect::<Vec<_>>().chunks(4)
        .map(|chunk| chunk.iter().collect::<String>()).collect::<Vec<_>>().join("-")
}

fn is_plain_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub(crate) fn decode_b64url(value: &str) -> Option<Vec<u8>> {
    crate::boss_key_text::decode(value)
}

#[cfg(test)]
pub(crate) mod tests_support {
    use super::BossPins;
    use std::cell::RefCell;

    thread_local! {
        static PINS: RefCell<Option<Vec<BossPins>>> = const { RefCell::new(None) };
        static DAMAGED: RefCell<bool> = const { RefCell::new(false) };
    }

    pub fn damaged() -> bool { DAMAGED.with(|flag| *flag.borrow()) }

    pub fn set_damaged(value: bool) { DAMAGED.with(|flag| *flag.borrow_mut() = value); }

    /// Tests never read the machine's real pins: they see none unless they set some here.
    pub fn override_pins() -> Option<Vec<BossPins>> {
        PINS.with(|pins| pins.borrow().clone()).or_else(|| Some(Vec::new()))
    }

    pub fn set_pins(pins: Option<Vec<BossPins>>) {
        PINS.with(|cell| *cell.borrow_mut() = pins);
    }
}

/// The key a signature must verify against: the pinned bytes when pinned; the offered key only
/// while this machine has no pins at all (before setup pinned any).
pub fn trusted_key(boss_id: &str, key_id: &str, offered: Vec<u8>) -> Result<Vec<u8>, &'static str> {
    match lookup(boss_id, key_id) {
        PinLookup::Pinned(bytes) => Ok(bytes),
        PinLookup::Revoked => Err("signing key revoked on this machine"),
        PinLookup::Unknown if any_pins() => Err("signed by a key this machine has not pinned; run `hiboss boss keys`"),
        PinLookup::Unknown => Ok(offered),
    }
}
