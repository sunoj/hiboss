// Purpose: Shared HTTP helpers for CLI setup flows and Telegram command registration.
// Exports: Telegram/Discord API helpers plus saved Telegram token extraction.
// Dependencies: reqwest, serde_json, crate::types, std::error::Error.

use crate::types::ChannelInfo;
use reqwest::Client;
use serde_json::{json, Value};
use std::error::Error;

pub async fn tg_api(http: &Client, token: &str, method: &str, body: &Value) -> Result<Value, Box<dyn Error>> {
    let resp = http
        .post(format!("https://api.telegram.org/bot{}/{}", token, method))
        .json(body)
        .send()
        .await?;
    if !resp.status().is_success() {
        return Err(format!("Telegram API {} failed ({})", method, resp.status()).into());
    }
    Ok(resp.json().await?)
}

pub async fn register_telegram_commands(http: &Client, bot_token: &str) -> Result<Value, Box<dyn Error>> {
    tg_api(
        http,
        bot_token,
        "setMyCommands",
        &json!({
            "commands": [
                { "command": "msg", "description": "Send a message to the AI agent" },
                { "command": "status", "description": "Show agent session status" }
            ]
        }),
    )
    .await
}

pub fn extract_chats(updates: &Value) -> Vec<(String, String)> {
    let mut chats: Vec<(String, String)> = Vec::new();
    let Some(arr) = updates["result"].as_array() else { return chats };
    for update in arr.iter().rev() {
        let chat = &update["message"]["chat"];
        let Some(id) = chat["id"].as_i64().map(|value| value.to_string()) else { continue };
        if chats.iter().any(|(chat_id, _)| chat_id == &id) { continue; }
        let title = chat["title"].as_str().or(chat["first_name"].as_str()).unwrap_or("?").to_owned();
        chats.push((id, title));
    }
    chats
}

pub fn select_chat(chats: &[(String, String)]) -> Result<String, Box<dyn Error>> {
    if chats.len() == 1 {
        eprintln!("found: {} ({})", chats[0].1, chats[0].0);
        return Ok(chats[0].0.clone());
    }
    eprintln!("found {} chats:\n", chats.len());
    for (index, (id, title)) in chats.iter().enumerate() {
        eprintln!("  [{}] {} (ID: {})", index + 1, title, id);
    }
    eprint!("\nSelect chat number [1]: ");
    std::io::Write::flush(&mut std::io::stderr())?;
    let mut choice = String::new();
    std::io::stdin().read_line(&mut choice)?;
    let idx: usize = choice.trim().parse().unwrap_or(1);
    if idx < 1 || idx > chats.len() {
        return Err("Invalid selection".into());
    }
    Ok(chats[idx - 1].0.clone())
}

pub async fn discord_api(http: &Client, token: &str, method: &str, path: &str, body: Option<&Value>) -> Result<Value, Box<dyn Error>> {
    let url = format!("https://discord.com/api/v10/{}", path);
    let mut req = if method == "POST" { http.post(&url) } else { http.get(&url) };
    req = req.header("Authorization", format!("Bot {}", token));
    if let Some(payload) = body {
        req = req.json(payload);
    }
    let resp = req.send().await?;
    if !resp.status().is_success() {
        return Err(format!("Discord API {} failed ({})", path, resp.status()).into());
    }
    Ok(resp.json().await?)
}

pub async fn list_text_channels(http: &Client, token: &str, guilds: &[Value]) -> Vec<(String, String, String)> {
    let mut all = Vec::new();
    for guild in guilds {
        let guild_id = guild["id"].as_str().unwrap_or_default();
        let guild_name = guild["name"].as_str().unwrap_or("?").to_owned();
        let path = format!("guilds/{}/channels", guild_id);
        let Ok(channels_val) = discord_api(http, token, "GET", &path, None).await else { continue };
        let Ok(channels): Result<Vec<Value>, _> = serde_json::from_value(channels_val) else { continue };
        for channel in &channels {
            if channel["type"].as_u64() == Some(0) {
                all.push((
                    channel["id"].as_str().unwrap_or("?").to_owned(),
                    channel["name"].as_str().unwrap_or("?").to_owned(),
                    guild_name.clone(),
                ));
            }
        }
    }
    all
}

pub fn extract_telegram_bot_token(channels: &[ChannelInfo]) -> Option<String> {
    channels
        .iter()
        .find(|channel| channel.enabled && channel.channel == "telegram")
        .and_then(|channel| channel.config.get("bot_token"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::extract_telegram_bot_token;
    use crate::types::ChannelInfo;
    use serde_json::json;

    #[test]
    fn extracts_saved_telegram_bot_token() {
        let channels = vec![
            ChannelInfo {
                id: "discord-1".to_owned(),
                channel: "discord".to_owned(),
                config: json!({ "bot_token": "discord-token" }),
                enabled: true,
                created_at: "2026-01-01T00:00:00Z".to_owned(),
            },
            ChannelInfo {
                id: "telegram-1".to_owned(),
                channel: "telegram".to_owned(),
                config: json!({ "bot_token": "telegram-token" }),
                enabled: true,
                created_at: "2026-01-01T00:00:00Z".to_owned(),
            },
        ];

        assert_eq!(extract_telegram_bot_token(&channels).as_deref(), Some("telegram-token"));
    }
}
