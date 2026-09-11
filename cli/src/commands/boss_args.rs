// Boss command argument contracts.
// Exports clap argument types; depends on clap derives.
use clap::{Args, Subcommand};

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
    /// Set boss quiet-hours preferences
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
    #[arg(long, help = "Quiet hours start (HH:MM, e.g. 22:00)")]
    pub quiet_start: Option<String>,
    #[arg(long, help = "Quiet hours end (HH:MM, e.g. 08:00)")]
    pub quiet_end: Option<String>,
    #[arg(long, help = "Timezone for quiet hours (e.g. Asia/Shanghai)")]
    pub timezone: Option<String>,

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
