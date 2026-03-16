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

pub async fn run(args: &BossArgs, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match &args.command {
        BossCommand::List => run_list(client).await,
        BossCommand::Add(payload) => run_add(payload, client).await,
        BossCommand::Remove(payload) => run_remove(payload, client).await,
        BossCommand::Update(payload) => run_update(payload, client).await,
        BossCommand::Grant(payload) => run_grant(payload, client).await,
        BossCommand::Revoke(payload) => run_revoke(payload, client).await,
        BossCommand::Show(payload) => run_show(payload, client).await,
    }
}

async fn run_list(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let resp = client.list_bosses().await?;
    if let Some(list) = resp["bosses"].as_array() {
        if list.is_empty() {
            eprintln!("No bosses found.");
            return Ok(());
        }
        println!("{:<10} {:<20} {:<12} {:<16} {:<16} {}", "ID", "Name", "Role", "Telegram", "Discord", "Agents");
        for boss in list {
            let id = short_id(boss["id"].as_str().unwrap_or(""));
            let name = boss["name"].as_str().unwrap_or("-");
            let role = boss["role"].as_str().unwrap_or("viewer");
            let telegram = boss["telegram_user_id"].as_str().unwrap_or("-");
            let discord = boss["discord_user_id"].as_str().unwrap_or("-");
            let agents = format_agents(boss);
            println!("{:<10} {:<20} {:<12} {:<16} {:<16} {}", id, name, color_role(role), telegram, discord, agents);
        }
        return Ok(());
    }
    eprintln!("No bosses found.");
    Ok(())
}

async fn run_add(args: &BossAddArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let mut payload = Map::new();
    payload.insert("name".into(), Value::String(args.name.clone()));
    payload.insert("role".into(), Value::String(args.role.clone()));
    insert_optional(&mut payload, "telegram_user_id", &args.telegram_user_id);
    insert_optional(&mut payload, "discord_user_id", &args.discord_user_id);
    let boss = client.create_boss(&Value::Object(payload)).await?;
    let id = boss["id"].as_str().unwrap_or("-");
    eprintln!("Boss created: {} ({})", boss["name"].as_str().unwrap_or("-"), short_id(id));
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
    if updates.is_empty() {
        eprintln!("No updates provided.");
        return Ok(());
    }
    let boss = client.update_boss(&args.id, &Value::Object(updates)).await?;
    eprintln!("Boss updated: {}", short_id(boss["id"].as_str().unwrap_or("")));
    print_boss_details(&boss);
    Ok(())
}

async fn run_grant(args: &BossGrantArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.grant_boss_access(&args.boss_id, &args.agent_id).await?;
    eprintln!("Access granted for agent {} to boss {}", short_id(&args.agent_id), short_id(&args.boss_id));
    Ok(())
}

async fn run_revoke(args: &BossRevokeArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.revoke_boss_access(&args.boss_id, &args.agent_id).await?;
    eprintln!("Access revoked for agent {} from boss {}", short_id(&args.agent_id), short_id(&args.boss_id));
    Ok(())
}

async fn run_show(args: &BossShowArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let boss = client.get_boss(&args.id).await?;
    print_boss_details(&boss);
    println!("Agents: {}", format_agents(&boss));
    Ok(())
}

fn print_boss_details(boss: &Value) {
    let id = boss["id"].as_str().unwrap_or("-");
    println!("ID: {}", short_id(id));
    println!("Name: {}", boss["name"].as_str().unwrap_or("-"));
    println!("Role: {}", color_role(boss["role"].as_str().unwrap_or("viewer")));
    println!("Telegram User ID: {}", boss["telegram_user_id"].as_str().unwrap_or("-"));
    println!("Discord User ID: {}", boss["discord_user_id"].as_str().unwrap_or("-"));
}

fn format_agents(boss: &Value) -> String {
    match boss["agents"].as_array().or_else(|| boss["access"].as_array()) {
        Some(list) if !list.is_empty() => list.iter().map(agent_label).collect::<Vec<_>>().join(", "),
        _ => "-".into(),
    }
}

fn agent_label(agent: &Value) -> String {
    if let Some(name) = agent["name"].as_str() {
        return name.to_string();
    }
    if let Some(id) = agent["id"].as_str().or_else(|| agent.as_str()) {
        return short_id(id);
    }
    "-".into()
}

fn insert_optional(map: &mut Map<String, Value>, key: &str, value: &Option<String>) {
    if let Some(value) = value {
        map.insert(key.into(), Value::String(value.clone()));
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
