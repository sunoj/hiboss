// Purpose: Manage boss identities and access control.
// Exports BossArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.
use crate::{client::HiBossClient, config::Config, helpers::short_id};
use clap::{Args, Subcommand};
use colored::Colorize;
use serde_json::{Map, Value};
use std::error::Error;

#[derive(Debug, Args)]
pub struct BossArgs {
    #[command(subcommand)]
    pub command: BossCommand,
}
#[derive(Debug, Subcommand)]
pub enum BossCommand {
    List,
    Add(BossAddArgs),
    Remove(BossRemoveArgs),
    Update(BossUpdateArgs),
    Grant(BossGrantArgs),
    Revoke(BossRevokeArgs),
    Show(BossShowArgs),
    /// Set boss preferences (channel, quiet hours, notifications)
    Preferences(BossPreferencesArgs),
    /// View messages from sub-agents (agent-as-boss)
    Inbox(BossInboxArgs),
    /// Reply to a sub-agent message as boss
    Reply(BossReplyArgs),
}
#[derive(Debug, Args)]
pub struct BossAddArgs {
    pub name: String,
    #[arg(long, default_value = "admin")]
    pub role: String,
    #[arg(long = "telegram-user-id")]
    pub telegram_user_id: Option<String>,
    #[arg(long = "discord-user-id")]
    pub discord_user_id: Option<String>,
    /// Link this boss to an agent (agent-as-boss)
    #[arg(long = "agent-id")]
    pub agent_id: Option<String>,
}
#[derive(Debug, Args)]
pub struct BossRemoveArgs {
    pub id: String,
}
#[derive(Debug, Args)]
pub struct BossUpdateArgs {
    pub id: String,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long)]
    pub role: Option<String>,
    #[arg(long = "telegram-user-id")]
    pub telegram_user_id: Option<String>,
    #[arg(long = "discord-user-id")]
    pub discord_user_id: Option<String>,
    /// Link/unlink this boss to an agent
    #[arg(long = "agent-id")]
    pub agent_id: Option<String>,
}
#[derive(Debug, Args)]
pub struct BossGrantArgs {
    pub boss_id: String,
    pub agent_id: String,
}
#[derive(Debug, Args)]
pub struct BossRevokeArgs {
    pub boss_id: String,
    pub agent_id: String,
}
#[derive(Debug, Args)]
pub struct BossShowArgs {
    pub id: String,
}
#[derive(Debug, Args)]
pub struct BossPreferencesArgs {
    pub id: String,
    #[arg(
        long,
        help = "Preferred channel: telegram, discord, email (or 'none' to clear)"
    )]
    pub channel: Option<String>,
    #[arg(long, help = "Quiet hours start (HH:MM, e.g. 22:00)")]
    pub quiet_start: Option<String>,
    #[arg(long, help = "Quiet hours end (HH:MM, e.g. 08:00)")]
    pub quiet_end: Option<String>,
    #[arg(long, help = "Timezone for quiet hours (e.g. Asia/Shanghai)")]
    pub timezone: Option<String>,
    #[arg(
        long,
        help = "Priority levels that trigger notifications (comma-separated)"
    )]
    pub notify: Option<String>,
}
#[derive(Debug, Args)]
pub struct BossInboxArgs {
    #[arg(long)]
    pub all: bool,
    #[arg(long)]
    pub priority: Option<String>,
    #[arg(long, default_value = "20")]
    pub limit: u32,
    #[arg(long)]
    pub count: bool,
}
#[derive(Debug, Args)]
pub struct BossReplyArgs {
    pub id: String,
    pub body: String,
}

pub async fn run(
    args: &BossArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        BossCommand::List => run_list(client).await,
        BossCommand::Add(payload) => run_add(payload, client).await,
        BossCommand::Remove(payload) => run_remove(payload, client).await,
        BossCommand::Update(payload) => run_update(payload, client).await,
        BossCommand::Grant(payload) => run_grant(payload, client).await,
        BossCommand::Revoke(payload) => run_revoke(payload, client).await,
        BossCommand::Show(payload) => run_show(payload, client).await,
        BossCommand::Preferences(payload) => run_preferences(payload, client).await,
        BossCommand::Inbox(payload) => run_inbox(payload, client).await,
        BossCommand::Reply(payload) => run_reply(payload, client).await,
    }
}

async fn run_list(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let resp = client.list_bosses().await?;
    let Some(list) = resp["bosses"].as_array().filter(|l| !l.is_empty()) else {
        eprintln!("No bosses found.");
        return Ok(());
    };
    println!(
        "{:<10} {:<20} {:<12} {:<16} {:<16} {}",
        "ID", "Name", "Role", "Telegram", "Discord", "Agents"
    );
    for b in list {
        println!(
            "{:<10} {:<20} {:<12} {:<16} {:<16} {}",
            short_id(b["id"].as_str().unwrap_or("")),
            b["name"].as_str().unwrap_or("-"),
            color_role(b["role"].as_str().unwrap_or("viewer")),
            b["telegram_user_id"].as_str().unwrap_or("-"),
            b["discord_user_id"].as_str().unwrap_or("-"),
            format_agents(b)
        );
    }
    Ok(())
}

async fn run_add(args: &BossAddArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let mut payload = Map::new();
    payload.insert("name".into(), Value::String(args.name.clone()));
    payload.insert("role".into(), Value::String(args.role.clone()));
    insert_optional(&mut payload, "telegram_user_id", &args.telegram_user_id);
    insert_optional(&mut payload, "discord_user_id", &args.discord_user_id);
    insert_optional(&mut payload, "agent_id", &args.agent_id);
    let boss = client.create_boss(&Value::Object(payload)).await?;
    let id = boss["id"].as_str().unwrap_or("-");
    eprintln!(
        "Boss created: {} ({})",
        boss["name"].as_str().unwrap_or("-"),
        short_id(id)
    );
    print_boss_details(&boss);
    Ok(())
}

async fn run_remove(args: &BossRemoveArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.delete_boss(&args.id).await?;
    eprintln!("Boss removed");
    Ok(())
}

async fn run_update(args: &BossUpdateArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let mut updates = Map::new();
    insert_optional(&mut updates, "name", &args.name);
    insert_optional(&mut updates, "role", &args.role);
    insert_optional(&mut updates, "telegram_user_id", &args.telegram_user_id);
    insert_optional(&mut updates, "discord_user_id", &args.discord_user_id);
    insert_optional(&mut updates, "agent_id", &args.agent_id);
    if updates.is_empty() {
        eprintln!("No updates provided.");
        return Ok(());
    }
    let boss = client
        .update_boss(&args.id, &Value::Object(updates))
        .await?;
    eprintln!(
        "Boss updated: {}",
        short_id(boss["id"].as_str().unwrap_or(""))
    );
    print_boss_details(&boss);
    Ok(())
}

async fn run_grant(args: &BossGrantArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client
        .grant_boss_access(&args.boss_id, &args.agent_id)
        .await?;
    eprintln!(
        "Access granted for agent {} to boss {}",
        short_id(&args.agent_id),
        short_id(&args.boss_id)
    );
    Ok(())
}

async fn run_revoke(args: &BossRevokeArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client
        .revoke_boss_access(&args.boss_id, &args.agent_id)
        .await?;
    eprintln!(
        "Access revoked for agent {} from boss {}",
        short_id(&args.agent_id),
        short_id(&args.boss_id)
    );
    Ok(())
}

async fn run_show(args: &BossShowArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let boss = client.get_boss(&args.id).await?;
    print_boss_details(&boss);
    println!("Agents: {}", format_agents(&boss));
    Ok(())
}

async fn run_preferences(
    args: &BossPreferencesArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let no_updates = args.channel.is_none()
        && args.quiet_start.is_none()
        && args.quiet_end.is_none()
        && args.timezone.is_none()
        && args.notify.is_none();
    if no_updates {
        // Show current preferences
        let boss = client.get_boss(&args.id).await?;
        eprintln!("Preferences for {}", boss["name"].as_str().unwrap_or("-"));
        if let Some(prefs) = boss["preferences"].as_object() {
            if prefs.is_empty() {
                println!("  (no preferences set)");
            } else {
                for (k, v) in prefs {
                    println!("  {}: {}", k, v);
                }
            }
        } else {
            println!("  (no preferences set)");
        }
        return Ok(());
    }
    let mut prefs = Map::new();
    if let Some(ref ch) = args.channel {
        if ch == "none" {
            prefs.insert("preferred_channel".into(), Value::Null);
        } else {
            prefs.insert("preferred_channel".into(), Value::String(ch.clone()));
        }
    }
    if args.quiet_start.is_some() || args.quiet_end.is_some() {
        let mut qh = Map::new();
        if let Some(ref s) = args.quiet_start {
            qh.insert("start".into(), Value::String(s.clone()));
        }
        if let Some(ref e) = args.quiet_end {
            qh.insert("end".into(), Value::String(e.clone()));
        }
        if let Some(ref tz) = args.timezone {
            qh.insert("timezone".into(), Value::String(tz.clone()));
        }
        prefs.insert("quiet_hours".into(), Value::Object(qh));
    }
    if let Some(ref n) = args.notify {
        let priorities: Vec<Value> = n
            .split(',')
            .map(|s| Value::String(s.trim().to_owned()))
            .collect();
        prefs.insert("notify_priorities".into(), Value::Array(priorities));
    }
    let mut payload = Map::new();
    payload.insert("preferences".into(), Value::Object(prefs));
    let boss = client
        .update_boss(&args.id, &Value::Object(payload))
        .await?;
    eprintln!(
        "Preferences updated for {}",
        boss["name"].as_str().unwrap_or("-")
    );
    if let Some(prefs) = boss["preferences"].as_object() {
        for (k, v) in prefs {
            println!("  {}: {}", k, v);
        }
    }
    Ok(())
}

async fn run_inbox(args: &BossInboxArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let resp = client
        .boss_inbox(!args.all, args.limit, args.priority.as_deref(), args.count)
        .await?;
    if args.count {
        println!("{}", resp["total"].as_u64().unwrap_or(0));
        return Ok(());
    }
    if let Some(list) = resp["messages"].as_array() {
        if list.is_empty() {
            eprintln!("No messages from sub-agents.");
            return Ok(());
        }
        println!(
            "{:<10} {:<15} {:<10} {:<10} {}",
            "ID", "Agent", "Priority", "Status", "Body"
        );
        for msg in list {
            let id = short_id(msg["id"].as_str().unwrap_or(""));
            let agent = msg["agent_name"].as_str().unwrap_or("-");
            let priority = msg["priority"].as_str().unwrap_or("normal");
            let status = msg["status"].as_str().unwrap_or("-");
            let body = msg["body"]
                .as_str()
                .unwrap_or("")
                .chars()
                .take(60)
                .collect::<String>();
            println!(
                "{:<10} {:<15} {:<10} {:<10} {}",
                id,
                agent,
                color_priority_str(priority),
                status,
                body
            );
        }
    }
    Ok(())
}

async fn run_reply(args: &BossReplyArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let resp = client.boss_reply(&args.id, &args.body).await?;
    let id = short_id(resp["id"].as_str().unwrap_or(""));
    eprintln!("Reply sent ({})", id);
    Ok(())
}

fn color_priority_str(priority: &str) -> colored::ColoredString {
    match priority {
        "critical" => priority.red().bold(),
        "high" => priority.yellow(),
        "normal" => priority.normal(),
        "low" => priority.dimmed(),
        _ => priority.normal(),
    }
}

fn print_boss_details(boss: &Value) {
    println!("ID: {}", short_id(boss["id"].as_str().unwrap_or("-")));
    println!("Name: {}", boss["name"].as_str().unwrap_or("-"));
    println!(
        "Role: {}",
        color_role(boss["role"].as_str().unwrap_or("viewer"))
    );
    println!(
        "Telegram: {}",
        boss["telegram_user_id"].as_str().unwrap_or("-")
    );
    println!(
        "Discord: {}",
        boss["discord_user_id"].as_str().unwrap_or("-")
    );
    if let Some(id) = boss["agent_id"].as_str() {
        println!("Agent: {}", short_id(id));
    }
}

fn format_agents(boss: &Value) -> String {
    boss["agents"]
        .as_array()
        .or_else(|| boss["access"].as_array())
        .filter(|l| !l.is_empty())
        .map(|l| {
            l.iter()
                .map(|a| {
                    a["name"]
                        .as_str()
                        .map(String::from)
                        .unwrap_or_else(|| short_id(a["id"].as_str().or(a.as_str()).unwrap_or("-")))
                })
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_else(|| "-".into())
}

fn insert_optional(map: &mut Map<String, Value>, key: &str, value: &Option<String>) {
    if let Some(v) = value {
        map.insert(key.into(), Value::String(v.clone()));
    }
}

fn color_role(role: &str) -> colored::ColoredString {
    match role {
        "admin" => role.red().bold(),
        "manager" => role.yellow(),
        "viewer" => role.green(),
        _ => role.normal(),
    }
}
