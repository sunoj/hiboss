// Runs the existing guided Discord channel wizard.
// Exports run_discord_setup within setup, preserving slash-command registration.
// Dependencies: setup prompts, HTTP helpers, Config, and HiBossClient.

use super::setup_support::{discord_api, list_text_channels};
use super::{SetupDiscordArgs, prompt};
use crate::{client::HiBossClient, config::Config};
use serde_json::{Value, json};
use std::error::Error;

pub(super) async fn run_discord_setup(
    args: &SetupDiscordArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let http = reqwest::Client::new();
    let server_url = config.require_server()?;

    // Step 1: Get bot token
    let bot_token = bot_token(args)?;

    // Validate and get app info
    eprint!("Validating bot token... ");
    let app = discord_api(&http, &bot_token, "GET", "oauth2/applications/@me", None).await?;
    let app_id = app["id"].as_str().unwrap_or("?").to_owned();
    let app_name = app["name"].as_str().unwrap_or("?");
    eprintln!("OK ({}, ID: {})", app_name, app_id);

    // Step 2: Select channel
    let channel_id = channel_id(args, &http, &bot_token, &app_id).await?;

    // Step 3: Register slash commands
    let base = server_url.trim_end_matches('/');
    register_commands(&http, base, &app_id, &bot_token).await?;

    // Step 4: Save config
    eprint!("  Saving channel config... ");
    let mut cfg = json!({ "bot_token": bot_token, "channel_id": channel_id });
    if let Some(ref wh_url) = args.webhook_url {
        cfg["webhook_url"] = json!(wh_url);
    }
    client.set_channel("discord", &cfg).await?;
    eprintln!("OK");

    eprintln!("\n=== Discord setup almost complete! ===\n");
    eprintln!("One manual step for boss → agent messaging:\n");
    eprintln!(
        "  1. Discord Developer Portal > {} > General Information",
        app_name
    );
    eprintln!("  2. Set Interactions Endpoint URL to:");
    eprintln!("     {}/api/webhooks/discord-interactions", base);
    eprintln!("  3. Copy PUBLIC KEY from same page, then run:");
    eprintln!("     wrangler secret put DISCORD_PUBLIC_KEY\n");
    eprintln!("Try: hiboss send \"Hello from Discord!\"");
    Ok(())
}

fn bot_token(args: &SetupDiscordArgs) -> Result<String, Box<dyn Error>> {
    Ok(if let Some(ref t) = args.bot_token {
        t.clone()
    } else {
        eprintln!("=== Discord Bot Setup ===\n");
        eprintln!("Step 1: Create a Discord application & bot");
        eprintln!("  1. Go to https://discord.com/developers/applications");
        eprintln!("  2. Click 'New Application' > create it");
        eprintln!("  3. Bot tab > 'Reset Token' > copy the token");
        eprintln!("  4. Enable MESSAGE CONTENT INTENT in Bot tab\n");
        let token = prompt("Paste your bot token: ")?;
        if token.is_empty() {
            return Err("Bot token is required".into());
        }
        token
    })
}

async fn channel_id(
    args: &SetupDiscordArgs,
    http: &reqwest::Client,
    bot_token: &str,
    app_id: &str,
) -> Result<String, Box<dyn Error>> {
    Ok(if let Some(ref id) = args.channel_id {
        id.clone()
    } else {
        eprintln!("\nStep 2: Select a Discord channel");
        eprintln!("  Invite the bot first:");
        eprintln!(
            "  https://discord.com/oauth2/authorize?client_id={}&scope=bot&permissions=2048\n",
            app_id
        );

        eprint!("Fetching channels... ");
        let guilds: Vec<Value> = serde_json::from_value(
            discord_api(&http, &bot_token, "GET", "users/@me/guilds", None).await?,
        )?;
        eprintln!("found {} server(s)", guilds.len());

        let channels = list_text_channels(&http, &bot_token, &guilds).await;
        if channels.is_empty() {
            return Err("No text channels found. Invite the bot first.".into());
        }

        eprintln!("\nAvailable channels:");
        for (i, (id, name, guild)) in channels.iter().enumerate() {
            eprintln!("  [{}] {} / #{} ({})", i + 1, guild, name, id);
        }
        let choice = prompt("\nSelect channel number [1]: ")?;
        let idx: usize = choice.parse().unwrap_or(1);
        if idx < 1 || idx > channels.len() {
            return Err("Invalid selection".into());
        }
        channels[idx - 1].0.clone()
    })
}

async fn register_commands(
    http: &reqwest::Client,
    base: &str,
    app_id: &str,
    bot_token: &str,
) -> Result<(), Box<dyn Error>> {
    eprint!("\nStep 3: Registering /msg slash command... ");
    let reg_resp = http
        .post(format!(
            "{}/api/webhooks/discord-interactions/register-commands",
            base
        ))
        .json(&json!({ "app_id": app_id, "bot_token": bot_token }))
        .send()
        .await?;
    if reg_resp.status().is_success() {
        eprintln!("OK");
    } else {
        eprintln!("FAILED ({})", reg_resp.text().await.unwrap_or_default());
    }
    Ok(())
}
