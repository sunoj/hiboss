// Purpose: Manage agent groups via the hiboss CLI.
// Exports: GroupArgs, GroupCommand, and run().
// Dependencies: clap, colored, crate::client, crate::config.

use crate::client::HiBossClient;
use crate::config::Config;
use crate::helpers::short_id;
use clap::{Args, Subcommand};
use colored::Colorize;
use std::error::Error;

#[derive(Debug, Args)]
pub struct GroupArgs {
    #[command(subcommand)]
    pub command: GroupCommand,
}

#[derive(Debug, Subcommand)]
pub enum GroupCommand {
    /// List all groups
    List,
    /// Create a new group
    Create(GroupCreateArgs),
    /// Show group details
    Show(GroupShowArgs),
    /// Delete a group
    Delete(GroupDeleteArgs),
    /// Add a member to a group
    AddMember(GroupMemberArgs),
    /// Remove a member from a group
    RemoveMember(GroupMemberArgs),
    /// Broadcast a message to all group members
    Broadcast(GroupBroadcastArgs),
}

#[derive(Debug, Args)]
pub struct GroupCreateArgs {
    /// Group name
    pub name: String,
    /// Optional description
    #[arg(long)]
    pub description: Option<String>,
}

#[derive(Debug, Args)]
pub struct GroupShowArgs {
    /// Group ID or name
    pub id: String,
}

#[derive(Debug, Args)]
pub struct GroupDeleteArgs {
    /// Group ID
    pub id: String,
}

#[derive(Debug, Args)]
pub struct GroupMemberArgs {
    /// Group ID
    pub group_id: String,
    /// Agent ID
    pub agent_id: String,
}

#[derive(Debug, Args)]
pub struct GroupBroadcastArgs {
    /// Group ID or name
    pub group_id: String,
    /// Message body
    pub body: String,
    /// Priority
    #[arg(long, default_value = "normal")]
    pub priority: String,
}

pub async fn run(
    args: &GroupArgs,
    _config: &Config,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    match &args.command {
        GroupCommand::List => run_list(client).await,
        GroupCommand::Create(a) => run_create(a, client).await,
        GroupCommand::Show(a) => run_show(a, client).await,
        GroupCommand::Delete(a) => run_delete(a, client).await,
        GroupCommand::AddMember(a) => run_add_member(a, client).await,
        GroupCommand::RemoveMember(a) => run_remove_member(a, client).await,
        GroupCommand::Broadcast(a) => run_broadcast(a, client).await,
    }
}

async fn run_list(client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let groups = client.list_groups().await?;
    let items = groups["groups"].as_array();
    if items.map_or(true, |a| a.is_empty()) {
        eprintln!("No groups found.");
        return Ok(());
    }
    println!("{:<10} {:<20} {:<8} {}", "ID", "Name", "Members", "Created");
    for g in items.unwrap() {
        let id = short_id(g["id"].as_str().unwrap_or(""));
        let name = g["name"].as_str().unwrap_or("-");
        let count = g["member_count"].as_u64().unwrap_or(0);
        let created = g["created_at"].as_str().unwrap_or("-");
        println!(
            "{:<10} {:<20} {:<8} {}",
            id.green(),
            name,
            count,
            created.dimmed()
        );
    }
    Ok(())
}

async fn run_create(args: &GroupCreateArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let group = client
        .create_group(&args.name, args.description.as_deref())
        .await?;
    let id = group["id"].as_str().unwrap_or("unknown");
    eprintln!("Group created: {} ({})", args.name, short_id(id));
    Ok(())
}

async fn run_show(args: &GroupShowArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let group = client.get_group(&args.id).await?;
    println!("Name: {}", group["name"].as_str().unwrap_or("-"));
    println!(
        "Description: {}",
        group["description"].as_str().unwrap_or("-")
    );
    let members = group["members"].as_array();
    println!("Members:");
    if let Some(members) = members {
        for m in members {
            let id = short_id(m["id"].as_str().unwrap_or(""));
            let name = m["name"].as_str().unwrap_or("-");
            println!("  {} {}", id.green(), name);
        }
    }
    Ok(())
}

async fn run_delete(args: &GroupDeleteArgs, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    client.delete_group(&args.id).await?;
    eprintln!("Group deleted");
    Ok(())
}

async fn run_add_member(
    args: &GroupMemberArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    client
        .add_group_member(&args.group_id, &args.agent_id)
        .await?;
    eprintln!("Member added");
    Ok(())
}

async fn run_remove_member(
    args: &GroupMemberArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    client
        .remove_group_member(&args.group_id, &args.agent_id)
        .await?;
    eprintln!("Member removed");
    Ok(())
}

async fn run_broadcast(
    args: &GroupBroadcastArgs,
    client: &HiBossClient,
) -> Result<(), Box<dyn Error>> {
    let result = client
        .broadcast_to_group(&args.group_id, &args.body, &args.priority)
        .await?;
    let count = result["count"].as_u64().unwrap_or(0);
    eprintln!("Broadcast sent to {} agents", count);
    Ok(())
}
