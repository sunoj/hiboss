// Purpose: Validate hiboss CLI configuration, connectivity, and channel delivery health.
// Exports: DoctorArgs and run().
// Dependencies: clap, colored, time, crate::client, crate::config, crate::types, std::process.

use clap::Args;
use colored::Colorize;
use crate::client::HiBossClient;
use crate::config::{config_path, Config};
use crate::types::{ChannelStats, ChannelStatsResponse, DeliveryErrorInfo, DeliveryQueueStatus, DirectionCount};
use std::{error::Error, process};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

#[derive(Debug, Args)]
pub struct DoctorArgs {
    #[arg(long)]
    pub verbose: bool,
}

#[derive(Default)]
struct DoctorReport {
    issues: u32,
    warnings: u32,
}

pub async fn run(args: &DoctorArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let mut report = DoctorReport::default();
    let (server, key) = print_local_checks(config, &mut report);
    if let (Some(url), Some(value)) = (server, key) {
        let client = HiBossClient::new(url, value);
        run_remote_checks(args, &client, &mut report).await;
    } else {
        print_channel_health_skip("missing server or key");
    }
    finish(report)
}

fn print_local_checks<'a>(config: &'a Config, report: &mut DoctorReport) -> (Option<&'a str>, Option<&'a str>) {
    let path = config_path();
    let exists = path.is_file();
    println!("Config file: {} {}", path.display(), if exists { "OK".green() } else { "MISSING".red() });
    if !exists {
        report.issues += 1;
    }

    let server = config.server.as_deref().filter(|value| !value.trim().is_empty());
    print_required("Server", server, "not set", report);
    let key = config.key.as_deref().filter(|value| !value.trim().is_empty());
    println!("Key: {} {}", key.map(mask_key).unwrap_or_else(|| "not set".to_string()), if key.is_some() { "OK".green() } else { report.issues += 1; "MISSING".red() });

    let channel = config.channel.as_deref().filter(|value| !value.trim().is_empty());
    if let Some(name) = channel {
        println!("Channel: {} {}", name, "OK".green());
    } else {
        println!("Channel: {} {}", "NOT SET", "WARN".yellow());
    }
    (server, key)
}

async fn run_remote_checks(args: &DoctorArgs, client: &HiBossClient, report: &mut DoctorReport) {
    match client.get_agent_config().await {
        Ok(agent) => print_agent_info(&agent),
        Err(err) => {
            println!("Agent: {} ({})", "FAIL".red(), err);
            report.issues += 1;
        }
    }

    match client.list_channels().await {
        Ok(channels) => print_channels(&channels.channels.iter().map(|info| info.channel.as_str()).collect::<Vec<_>>()),
        Err(err) => {
            println!("Channels: {} ({})", "FAIL".red(), err);
            report.issues += 1;
        }
    }

    match client.list_channel_stats(args.verbose).await {
        Ok(stats) => report.warnings += print_channel_health(&stats, args.verbose),
        Err(err) => {
            println!("📡 Channel Health");
            println!("  {} ({})", "FAIL".red(), err);
            report.issues += 1;
        }
    }
}

fn print_required(label: &str, value: Option<&str>, missing: &str, report: &mut DoctorReport) {
    if let Some(found) = value {
        println!("{label}: {} {}", found, "OK".green());
    } else {
        println!("{label}: {} {}", missing, "MISSING".red());
        report.issues += 1;
    }
}

fn print_agent_info(agent: &serde_json::Value) {
    let name = agent["name"].as_str().unwrap_or("-");
    println!("Agent: {} {}", name, "OK".green());
    if let Some(routing) = agent["channel_routing"].as_object() {
        if routing.is_empty() {
            println!("Routing: {} (messages need --channel or config.channel fallback)", "none".yellow());
            return;
        }
        let pairs: Vec<String> = routing.iter()
            .map(|(key, value)| format!("{key}→{}", value.as_str().unwrap_or("?")))
            .collect();
        println!("Routing: {} {}", pairs.join(", "), "OK".green());
        return;
    }
    println!("Routing: {} (messages need --channel or config.channel fallback)", "none".yellow());
}

fn print_channels(channels: &[&str]) {
    if channels.is_empty() {
        println!("Channels: NONE");
    } else {
        println!("Channels: {}", channels.join(", "));
    }
}

fn print_channel_health(stats: &ChannelStatsResponse, verbose: bool) -> u32 {
    println!("📡 Channel Health");
    if stats.channels.is_empty() {
        println!("  no channel delivery data");
    } else {
        for channel in &stats.channels {
            println!("{}", format_channel_line(channel));
        }
    }
    if verbose {
        print_recent_errors(&stats.recent_errors);
        print_delivery_queue(stats.delivery_queue.as_ref());
        print_direction_counts(&stats.direction_counts);
    }
    stats.channels.iter().filter(|channel| channel.total_failed > 0).count() as u32
}

fn print_recent_errors(errors: &[DeliveryErrorInfo]) {
    println!("  Recent delivery errors:");
    if errors.is_empty() {
        println!("    none");
        return;
    }
    for error in errors {
        let when = describe_timestamp(error.last_error_at.as_deref());
        let message = error.last_error.as_deref().unwrap_or("-");
        println!("    {}  {}  {}", error.channel, when, message);
    }
}

fn print_delivery_queue(queue: Option<&DeliveryQueueStatus>) {
    println!("  Delivery queue:");
    let Some(queue) = queue else {
        println!("    table not present");
        return;
    };
    println!("    total: {}", queue.total);
    if let Some(oldest_at) = queue.oldest_at.as_deref() {
        println!("    oldest: {}", describe_timestamp(Some(oldest_at)));
    }
    if queue.by_status.is_empty() {
        return;
    }
    let summary = queue.by_status.iter()
        .map(|entry| format!("{}={}", entry.status, entry.total))
        .collect::<Vec<_>>()
        .join(", ");
    println!("    by status: {}", summary);
}

fn print_direction_counts(counts: &[DirectionCount]) {
    println!("  Message counts by direction:");
    if counts.is_empty() {
        println!("    none");
        return;
    }
    for count in counts {
        println!("    {:<10} {:<14} {}", count.channel, count.direction, count.total);
    }
}

fn format_channel_line(channel: &ChannelStats) -> String {
    let icon = if channel.total_failed > 0 { "⚠".yellow() } else { "✅".green() };
    let summary = format!("{}/{} delivered", channel.total_delivered, channel.total_sent);
    let detail = if channel.total_failed > 0 {
        let error = channel.last_error.as_deref().unwrap_or("unknown error");
        let when = channel.last_error_at.as_deref().map(relative_time).unwrap_or_else(|| "unknown".to_string());
        format!("last error: \"{}\" ({})", error, when)
    } else if let Some(last_delivery_at) = channel.last_delivery_at.as_deref() {
        format!("last: {}", relative_time(last_delivery_at))
    } else {
        "last: never".to_string()
    };
    format!("  {:<10} {} {:<17} {}", channel.channel, icon, summary, detail)
}

fn relative_time(value: &str) -> String {
    let Ok(then) = OffsetDateTime::parse(value, &Rfc3339) else {
        return value.to_string();
    };
    let seconds = (OffsetDateTime::now_utc() - then).whole_seconds();
    format_age(seconds)
}

fn describe_timestamp(value: Option<&str>) -> String {
    let Some(timestamp) = value else {
        return "-".to_string();
    };
    format!("{} ({})", timestamp, relative_time(timestamp))
}

fn format_age(seconds: i64) -> String {
    if seconds < 60 {
        return "just now".to_string();
    }
    let minute = 60;
    let hour = minute * 60;
    let day = hour * 24;
    if seconds < hour {
        return format!("{}m ago", seconds / minute);
    }
    if seconds < day {
        return format!("{}h ago", seconds / hour);
    }
    format!("{}d ago", seconds / day)
}

fn finish(report: DoctorReport) -> Result<(), Box<dyn Error>> {
    if report.issues == 0 && report.warnings == 0 {
        println!("All checks passed");
        return Ok(());
    }
    if report.issues == 0 {
        println!("All required checks passed ({} warning{})", report.warnings, if report.warnings == 1 { "" } else { "s" });
        return Ok(());
    }
    println!("{} issues found", report.issues);
    process::exit(1);
}

fn print_channel_health_skip(reason: &str) {
    println!("📡 Channel Health");
    println!("  skipped ({reason})");
}

fn mask_key(value: &str) -> String {
    if value.len() <= 8 {
        value.to_string()
    } else {
        let start = &value[..4];
        let end = &value[value.len() - 4..];
        format!("{}...{}", start, end)
    }
}
