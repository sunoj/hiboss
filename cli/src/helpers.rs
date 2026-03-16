// Purpose: Shared display helpers for CLI output formatting.
// Exports: short_id, truncate, color_priority.
// Dependencies: colored.

use colored::Colorize;

pub fn short_id(value: &str) -> String {
    value.chars().take(8).collect()
}

pub fn truncate(input: &str, limit: usize) -> String {
    if input.chars().count() <= limit {
        input.to_string()
    } else {
        let truncated: String = input.chars().take(limit - 3).collect();
        format!("{}...", truncated)
    }
}

pub fn color_priority(priority: &str) -> colored::ColoredString {
    match priority {
        "critical" => priority.red().bold(),
        "high" => priority.yellow().bold(),
        "normal" => priority.green(),
        "low" => priority.white(),
        _ => priority.normal(),
    }
}
