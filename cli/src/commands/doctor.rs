// Purpose: Validate hiboss CLI configuration, hooks and connectivity.
// Exports: DoctorArgs and run().
// Dependencies: clap, colored, crate::client, crate::config, std::process.

use crate::client::HiBossClient;
use crate::config::{Config, config_path, resolve_credentials};
use clap::Args;
use colored::Colorize;
use std::{error::Error, process};

#[derive(Debug, Args)]
pub struct DoctorArgs {}

#[derive(Default)]
struct DoctorReport {
    issues: u32,
    warnings: u32,
}

pub async fn run(_args: &DoctorArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let mut report = DoctorReport::default();
    if super::claude_profiles::doctor()? {
        report.issues += 1;
    }
    let credential = resolve_credentials(config)?;
    print_local_checks(&credential.server, &credential.key, &mut report);
    let client = HiBossClient::new(&credential.server, &credential.key);
    run_remote_checks(&client, &mut report).await;
    finish(report)
}

fn print_local_checks(server: &str, key: &str, report: &mut DoctorReport) {
    let path = config_path();
    let exists = if std::env::var_os("HIBOSS_SERVER").is_some() {
        false // Rule 1 must not stat the config file.
    } else {
        path.is_file()
    };
    println!(
        "Config file: {} {}",
        path.display(),
        if exists {
            "OK".green()
        } else {
            "MISSING".red()
        }
    );
    if !exists && std::env::var_os("HIBOSS_SERVER").is_none() {
        report.issues += 1;
    }

    println!("Server: {} {}", server, "OK".green());
    println!("Key: {} {}", mask_key(key), "OK".green());
}

async fn run_remote_checks(client: &HiBossClient, report: &mut DoctorReport) {
    match client.get_agent_config().await {
        Ok(agent) => print_agent_info(&agent),
        Err(err) => {
            println!("Agent: {} ({})", "FAIL".red(), err);
            report.issues += 1;
        }
    }

}

fn print_agent_info(agent: &serde_json::Value) {
    let name = agent["name"].as_str().unwrap_or("-");
    println!("Agent: {} {}", name, "OK".green());
}

fn finish(report: DoctorReport) -> Result<(), Box<dyn Error>> {
    if report.issues == 0 && report.warnings == 0 {
        println!("All checks passed");
        return Ok(());
    }
    if report.issues == 0 {
        println!(
            "All required checks passed ({} warning{})",
            report.warnings,
            if report.warnings == 1 { "" } else { "s" }
        );
        return Ok(());
    }
    println!("{} issues found", report.issues);
    process::exit(1);
}

fn mask_key(value: &str) -> String {
    if value.chars().count() <= 4 { return "...".into(); }
    let tail: String = value
        .chars()
        .rev()
        .take(4)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    format!("...{tail}")
}

#[cfg(test)]
#[path = "doctor_tests.rs"]
mod tests;
