// Purpose: Manage agent identities (create, list).
// Exports: AgentArgs and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::client::HiBossClient;
use crate::config::Config;
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct AgentArgs {
    #[command(subcommand)]
    pub command: AgentCommand,
}

#[derive(Debug, Subcommand)]
pub enum AgentCommand {
    Create(CreateArgs),
    List,
    #[command(about = "View or update agent configuration")]
    Config(AgentConfigArgs),
}

#[derive(Debug, Args)]
pub struct CreateArgs {
    #[arg(value_name = "name")]
    pub name: String,
}

#[derive(Debug, Args)]
pub struct AgentConfigArgs {
    /// Set default priority (critical, high, normal, low)
    #[arg(long = "default-priority")]
    pub default_priority: Option<String>,
    /// Set rate limit (messages per minute, 0 = unlimited)
    #[arg(long = "rate-limit")]
    pub rate_limit: Option<u32>,
    /// Set per-priority channel routing (e.g. "normal=discord,high=telegram").
    /// Server uses this when CLI omits --channel. Set "none" to clear.
    #[arg(long = "channel-routing")]
    pub channel_routing: Option<String>,
    /// Set avatar image (local file path or URL). Used in Discord webhook mode.
    /// Set "none" to clear.
    #[arg(long = "avatar")]
    pub avatar: Option<String>,
    /// Set session role (orchestrator, worker, reviewer). Set "none" to clear.
    #[arg(long)]
    pub role: Option<String>,
    /// Set session info JSON (e.g. '{"branch":"main","cwd":"/project"}').
    /// Set "none" to clear.
    #[arg(long = "session-info")]
    pub session_info: Option<String>,
}

pub async fn run(command: &AgentCommand, _config: &Config, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    match command {
        AgentCommand::Create(args) => {
            let resp = client.create_agent(&args.name).await?;
            eprintln!("Agent created: {}", resp.name);
            println!("{}", resp.key);
        }
        AgentCommand::Config(args) => {
            if args.default_priority.is_none() && args.rate_limit.is_none() && args.channel_routing.is_none() && args.avatar.is_none() && args.role.is_none() && args.session_info.is_none() {
                let info = client.get_agent_config().await?;
                println!("default_priority: {}", info["default_priority"].as_str().unwrap_or("normal"));
                let rl = match &info["rate_limit"] {
                    serde_json::Value::Number(n) => n.to_string(),
                    _ => "unlimited".to_string(),
                };
                println!("rate_limit: {} msg/min", rl);
                print_channel_routing(&info["channel_routing"]);
                println!("avatar: {}", info["avatar_url"].as_str().unwrap_or("none"));
                println!("role: {}", info["role"].as_str().unwrap_or("none"));
                if let Some(si) = info.get("session_info") {
                    if !si.is_null() {
                        println!("session_info: {}", si);
                    }
                }
            } else {
                let mut updates = serde_json::Map::new();
                if let Some(dp) = &args.default_priority {
                    updates.insert("default_priority".into(), serde_json::Value::String(dp.clone()));
                }
                if let Some(rl) = args.rate_limit {
                    if rl == 0 {
                        updates.insert("rate_limit".into(), serde_json::Value::Null);
                    } else {
                        updates.insert("rate_limit".into(), serde_json::json!(rl));
                    }
                }
                if let Some(cr) = &args.channel_routing {
                    if cr == "none" || cr.is_empty() {
                        updates.insert("channel_routing".into(), serde_json::Value::Null);
                    } else {
                        let routing: serde_json::Map<String, serde_json::Value> = cr
                            .split(',')
                            .filter_map(|pair| {
                                let mut parts = pair.splitn(2, '=');
                                let key = parts.next()?.trim().to_string();
                                let val = parts.next()?.trim().to_string();
                                Some((key, serde_json::Value::String(val)))
                            })
                            .collect();
                        updates.insert("channel_routing".into(), serde_json::Value::Object(routing));
                    }
                }
                if let Some(role) = &args.role {
                    if role == "none" || role.is_empty() {
                        updates.insert("role".into(), serde_json::Value::Null);
                    } else {
                        updates.insert("role".into(), serde_json::Value::String(role.clone()));
                    }
                }
                if let Some(si) = &args.session_info {
                    if si == "none" || si.is_empty() {
                        updates.insert("session_info".into(), serde_json::Value::Null);
                    } else if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(si) {
                        updates.insert("session_info".into(), parsed);
                    } else {
                        eprintln!("Warning: session_info must be valid JSON, skipping");
                    }
                }
                if let Some(avatar) = &args.avatar {
                    if avatar == "none" || avatar.is_empty() {
                        updates.insert("avatar_url".into(), serde_json::Value::Null);
                    } else if avatar.starts_with("http://") || avatar.starts_with("https://") {
                        updates.insert("avatar_url".into(), serde_json::Value::String(avatar.clone()));
                    } else {
                        // Local file: upload to R2 first
                        let upload = client.upload_file(avatar).await?;
                        eprintln!("Uploaded avatar: {}", upload.url);
                        updates.insert("avatar_url".into(), serde_json::Value::String(upload.url));
                    }
                }
                let result = client.update_agent_config(&serde_json::Value::Object(updates)).await?;
                eprintln!("Config updated");
                println!("default_priority: {}", result["default_priority"].as_str().unwrap_or("normal"));
                let rl = match &result["rate_limit"] {
                    serde_json::Value::Number(n) => n.to_string(),
                    _ => "unlimited".to_string(),
                };
                println!("rate_limit: {} msg/min", rl);
                print_channel_routing(&result["channel_routing"]);
                println!("avatar: {}", result["avatar_url"].as_str().unwrap_or("none"));
                println!("role: {}", result["role"].as_str().unwrap_or("none"));
                if let Some(si) = result.get("session_info") {
                    if !si.is_null() {
                        println!("session_info: {}", si);
                    }
                }
            }
        }
        AgentCommand::List => {
            let resp = client.list_agents().await?;
            println!("{:<10} {:<20} {:<14} {:<10} {:<16} {}", "ID", "Name", "Role", "Status", "Branch", "Last Seen");
            for agent in resp.agents {
                let id: String = agent.id.chars().take(8).collect();
                let last = agent.last_used_at.as_deref().unwrap_or("-");
                let role = agent.role.as_deref().unwrap_or("-");
                let status_str = agent.status.as_deref().unwrap_or("offline");
                let branch = agent.session_info
                    .as_ref()
                    .and_then(|si| si.get("branch"))
                    .and_then(|b| b.as_str())
                    .unwrap_or("-");
                let colored_status = match status_str {
                    "online" => status_str.green().bold(),
                    "idle" => status_str.yellow().normal(),
                    _ => status_str.red().normal(),
                };
                let colored_role = match role {
                    "orchestrator" => role.magenta().bold(),
                    "worker" => role.cyan().normal(),
                    "reviewer" => role.yellow().normal(),
                    _ => role.dimmed(),
                };
                println!("{:<10} {:<20} {:<14} {:<10} {:<16} {}", id, agent.name.green(), colored_role, colored_status, branch.blue(), last.dimmed());
            }
        }
    }
    Ok(())
}

fn print_channel_routing(value: &serde_json::Value) {
    match value {
        serde_json::Value::Object(map) if !map.is_empty() => {
            let pairs: Vec<String> = map.iter()
                .map(|(k, v)| format!("{}={}", k, v.as_str().unwrap_or("?")))
                .collect();
            println!("channel_routing: {}", pairs.join(", "));
        }
        _ => println!("channel_routing: none"),
    }
}

