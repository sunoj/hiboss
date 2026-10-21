// Authenticated Discord slash-command registration against the HiBoss server.
// Adds a client operation with status-only errors to keep channel credentials private.
use super::HiBossClient;
use std::error::Error;

impl HiBossClient {
    pub async fn register_discord_commands(
        &self,
        app_id: &str,
        bot_token: &str,
    ) -> Result<(), Box<dyn Error>> {
        let response = self
            .http
            .post(format!(
                "{}/api/webhooks/discord-interactions/register-commands",
                self.base_url
            ))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "app_id": app_id, "bot_token": bot_token }))
            .send()
            .await
            .map_err(|_| "Discord command registration request failed")?;
        if !response.status().is_success() {
            return Err(format!(
                "Discord command registration failed ({})",
                response.status()
            )
            .into());
        }
        Ok(())
    }
}
