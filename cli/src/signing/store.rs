// Purpose: Hold an agent's P-256 signing key and persist it beside the CLI config.
// Exports: AgentSigner, key_file, load_signer, load_or_create_pending, commit_pending.
// Dependencies: ring ECDSA/SHA-256, serde_json, crate::config path and private writes.

use super::jws::encode;
use crate::config::{config_path, write_private};
use ring::digest::{SHA256, digest};
use ring::rand::SystemRandom;
use ring::signature::{ECDSA_P256_SHA256_FIXED_SIGNING, EcdsaKeyPair, KeyPair};
use serde::{Deserialize, Serialize};
use std::{error::Error, fs, path::PathBuf};

/// A credential's signing key plus the server identities it was enrolled for.
pub struct AgentSigner {
    pair: EcdsaKeyPair,
    rng: SystemRandom,
    pub public_key: String,
    pub key_id: String,
    pub agent_id: String,
    pub agent_key_id: String,
}

#[derive(Serialize, Deserialize)]
struct KeyFile {
    version: u8,
    agent_id: String,
    agent_key_id: String,
    key_id: String,
    pkcs8: String,
}

impl AgentSigner {
    fn from_pkcs8(pkcs8: &[u8], agent_id: &str, agent_key_id: &str) -> Result<Self, Box<dyn Error>> {
        let rng = SystemRandom::new();
        let pair = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, pkcs8, &rng)
            .map_err(|_| "signing key file holds an invalid P-256 key")?;
        let public = pair.public_key().as_ref().to_vec();
        Ok(Self {
            key_id: encode(digest(&SHA256, &public).as_ref()),
            public_key: encode(&public),
            pair,
            rng,
            agent_id: agent_id.to_owned(),
            agent_key_id: agent_key_id.to_owned(),
        })
    }

    /// An in-memory key for tests; never written to disk.
    #[cfg(test)]
    pub(crate) fn ephemeral(agent_id: &str, agent_key_id: &str) -> Self {
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &SystemRandom::new())
            .expect("test key");
        Self::from_pkcs8(pkcs8.as_ref(), agent_id, agent_key_id).expect("parse test key")
    }

    /// Raw 64-byte ES256 signature (r || s) over `input`.
    pub fn sign(&self, input: &[u8]) -> Result<Vec<u8>, Box<dyn Error>> {
        let signature = self.pair.sign(&self.rng, input).map_err(|_| "ES256 signing failed")?;
        Ok(signature.as_ref().to_vec())
    }
}

/// Keys live beside the real config file, so a symlinked config still finds its key.
fn signing_dir() -> PathBuf {
    let path = config_path();
    let real = fs::canonicalize(&path).unwrap_or(path);
    real.parent().map(|parent| parent.join("signing")).unwrap_or_else(|| PathBuf::from("signing"))
}

/// One file per credential, named by a digest of the bearer so the bearer never appears on disk twice.
pub fn key_file(bearer: &str) -> PathBuf {
    let name: String = digest(&SHA256, bearer.as_bytes()).as_ref()[..16]
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    signing_dir().join(format!("{name}.json"))
}

fn pending_file(bearer: &str) -> PathBuf {
    key_file(bearer).with_extension("pending.json")
}

fn read(path: &PathBuf) -> Result<Option<AgentSigner>, Box<dyn Error>> {
    let body = match fs::read(path) {
        Ok(body) => body,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let file: KeyFile = serde_json::from_slice(&body)
        .map_err(|_| format!("signing key file {} is malformed", path.display()))?;
    let pkcs8 = crate::message_security::decode(&file.pkcs8)?;
    let signer = AgentSigner::from_pkcs8(&pkcs8, &file.agent_id, &file.agent_key_id)?;
    if file.version != 1 || signer.key_id != file.key_id {
        return Err(format!("signing key file {} does not match its key", path.display()).into());
    }
    Ok(Some(signer))
}

/// The enrolled signer for this bearer credential, if this device has one.
pub fn load_signer(bearer: &str) -> Result<Option<AgentSigner>, Box<dyn Error>> {
    read(&key_file(bearer))
}

/// Reuses an unconfirmed key from an interrupted enrollment, or creates one.
pub fn load_or_create_pending(
    bearer: &str,
    agent_id: &str,
    agent_key_id: &str,
) -> Result<AgentSigner, Box<dyn Error>> {
    let path = pending_file(bearer);
    if let Some(signer) = read(&path)? {
        if signer.agent_id == agent_id && signer.agent_key_id == agent_key_id {
            return Ok(signer);
        }
    }
    let rng = SystemRandom::new();
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &rng)
        .map_err(|_| "could not generate a P-256 signing key")?;
    let signer = AgentSigner::from_pkcs8(pkcs8.as_ref(), agent_id, agent_key_id)?;
    let file = KeyFile {
        version: 1,
        agent_id: agent_id.to_owned(),
        agent_key_id: agent_key_id.to_owned(),
        key_id: signer.key_id.clone(),
        pkcs8: encode(pkcs8.as_ref()),
    };
    create_private_dir(&signing_dir())?;
    write_private(&path, &serde_json::to_vec_pretty(&file)?)?;
    Ok(signer)
}

/// Promotes the pending key once the server has bound it.
pub fn commit_pending(bearer: &str) -> Result<(), Box<dyn Error>> {
    fs::rename(pending_file(bearer), key_file(bearer))?;
    Ok(())
}

/// Deletes the key of a credential that no longer exists (after rotation).
pub fn remove_signer(bearer: &str) -> Result<(), Box<dyn Error>> {
    match fs::remove_file(key_file(bearer)) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error.into()),
        _ => Ok(()),
    }
}

fn create_private_dir(path: &PathBuf) -> Result<(), Box<dyn Error>> {
    fs::create_dir_all(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}
