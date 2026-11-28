// Purpose: The boss key directory an agent pins from (GET /api/agents/me/boss-keys).
// Exports: BossKeysResponse, DirectoryBoss, DirectoryKey and HiBossClient::get_boss_keys.
// Dependencies: serde, super::HiBossClient.
use super::HiBossClient;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct DirectoryKey {
    pub key_id: String,
    pub public_key: String,
    pub client_kind: String,
    pub label: Option<String>,
    pub created_at: String,
    pub revoked_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DirectoryBoss {
    pub boss_id: String,
    pub name: String,
    pub keys: Vec<DirectoryKey>,
}

#[derive(Debug, Deserialize)]
pub struct BossKeysResponse {
    pub bosses: Vec<DirectoryBoss>,
}

impl HiBossClient {
    client_endpoints! {
        get_boss_keys() -> BossKeysResponse = GET "/api/agents/me/boss-keys";
    }
}
