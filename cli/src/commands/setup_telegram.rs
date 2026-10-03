// Runs the existing guided Telegram channel wizard.
// Exports run_telegram_setup within setup, preserving channel and webhook behavior.
// Dependencies: setup prompts, HTTP helpers, Config, and HiBossClient.

use super::setup_support::{
    extract_chats, select_chat, telegram_set_webhook_payload, telegram_webhook_secret_reminder,
    tg_api,
};
use super::{SetupTelegramArgs, prompt};
use crate::{client::HiBossClient, config::Config};
use serde_json::{Value, json};
use std::error::Error;

pub(super) async fn run_telegram_setup(
    args: &SetupTelegramArgs,
    config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let http = reqwest::Client::new();
    let server_url = config.require_server()?;

    // Step 1: Get bot token
    let bot_token = bot_token(args)?;

    // Validate token
    eprint!("Validating bot token... ");
    let me: Value = tg_api(&http, &bot_token, "getMe", &json!({})).await?;
    let bot_name = me["result"]["username"].as_str().unwrap_or("unknown");
    eprintln!("OK (@{})", bot_name);

    // Step 2: Get chat ID
    let chat_id = chat_id(args, &http, &bot_token, bot_name).await?;

    // Step 3: Save config + webhook
    eprintln!("\nStep 3: Saving configuration...");
    let mut cfg = json!({ "chat_id": chat_id, "bot_token": bot_token });
    if args.use_topics {
        cfg["use_topics"] = json!(true);
    }
    client.set_channel("telegram", &cfg).await?;
    eprintln!("  Channel config saved.");

    set_webhook(&http, &bot_token, &server_url, args).await?;

    send_test(&http, &bot_token, &chat_id).await;

    eprintln!("\n=== Telegram setup complete! ===");
    eprintln!("Bot @{} connected to chat {}.", bot_name, chat_id);
    if let Some(reminder) = telegram_webhook_secret_reminder(args.webhook_secret.as_deref()) {
        eprintln!("{}", reminder);
    }
    eprintln!("Try: hiboss send \"Hello from my agent!\"");
    Ok(())
}

fn bot_token(args: &SetupTelegramArgs) -> Result<String, Box<dyn Error>> {
    Ok(if let Some(ref t) = args.bot_token {
        t.clone()
    } else {
        eprintln!("=== Telegram Bot Setup ===\n");
        eprintln!("Step 1: Create a Telegram bot");
        eprintln!("  1. Open Telegram and message @BotFather");
        eprintln!("  2. Send /newbot and follow the prompts");
        eprintln!("  3. Copy the bot token (looks like 123456:ABC-DEF...)\n");
        let token = prompt("Paste your bot token: ")?;
        if token.is_empty() {
            return Err("Bot token is required".into());
        }
        token
    })
}

async fn chat_id(
    args: &SetupTelegramArgs,
    http: &reqwest::Client,
    bot_token: &str,
    bot_name: &str,
) -> Result<String, Box<dyn Error>> {
    Ok(if let Some(ref id) = args.chat_id {
        id.clone()
    } else {
        eprintln!("\nStep 2: Connect bot to a chat");
        eprintln!(
            "  1. Add @{} to a group, OR send it a direct message",
            bot_name
        );
        eprintln!("  2. Send any message to the bot/group now\n");
        prompt("Press Enter when you've sent a message... ")?;

        eprint!("Detecting chat ID... ");
        let updates: Value = tg_api(
            &http,
            &bot_token,
            "getUpdates",
            &json!({"limit": 10, "offset": -10}),
        )
        .await?;
        let chats = extract_chats(&updates);
        if chats.is_empty() {
            eprintln!("FAILED");
            eprintln!("\nNo messages found. Ensure you sent a message after creating the bot.");
            eprintln!("Manual fallback: hiboss setup telegram --bot-token <token> --chat-id <id>");
            return Err("No chats detected".into());
        }
        select_chat(&chats)?
    })
}

async fn set_webhook(
    http: &reqwest::Client,
    bot_token: &str,
    server_url: &str,
    args: &SetupTelegramArgs,
) -> Result<(), Box<dyn Error>> {
    let base = server_url.trim_end_matches('/');
    let webhook_url = format!("{}/api/webhooks/telegram", base);
    eprint!("  Setting webhook... ");
    let wh: Value = tg_api(
        &http,
        &bot_token,
        "setWebhook",
        &telegram_set_webhook_payload(&webhook_url, args.webhook_secret.as_deref()),
    )
    .await?;
    if wh["ok"].as_bool() == Some(true) {
        eprintln!("OK");
    } else {
        eprintln!("WARNING: {}", wh["description"].as_str().unwrap_or("?"));
    }
    Ok(())
}

async fn send_test(http: &reqwest::Client, bot_token: &str, chat_id: &str) {
    // Step 4: Test message
    eprint!("  Sending test message... ");
    let test = tg_api(
        &http,
        &bot_token,
        "sendMessage",
        &json!({
            "chat_id": chat_id,
            "text": "hiboss connected! This bot will relay messages between you and your AI agents."
        }),
    )
    .await;
    if test.is_ok() {
        eprintln!("OK");
    } else {
        eprintln!("FAILED (check permissions)");
    }
}
