// Builds and identifies the exact lifecycle commands written by hiboss.
// Exports command rendering and ownership matching for setup and removal.
// Dependencies: setup_hooks event labels and shell-like command tokenization.

use std::path::Path;

pub(super) fn profile_hook_command(
    command_label: &str,
    project_dir: Option<&str>,
    runtime: &str,
) -> String {
    let label = command_label
        .strip_prefix("--codex-input ")
        .unwrap_or(command_label);
    let command_label = if runtime == "codex" {
        format!("--codex-input {label}")
    } else {
        label.to_owned()
    };
    if let Some(dir) = project_dir {
        return format!(
            "HIBOSS_PROFILE={runtime} HIBOSS_PROJECT_DIR={} hiboss hook {command_label}",
            shell_escape(dir)
        );
    }
    format!("HIBOSS_PROFILE={runtime} hiboss hook {command_label}")
}

pub(super) fn managed_hook_label(command: &str) -> Option<String> {
    let words = shell_words(command)?;
    let hook = words.iter().position(|word| word == "hook")?;
    if hook == 0 || !is_hiboss_executable(&words[hook - 1]) {
        return None;
    }
    if !managed_prefix(&words[..hook - 1]) {
        return None;
    }
    let label = if words
        .get(hook + 1)
        .is_some_and(|word| word == "--codex-input")
    {
        if hook + 3 != words.len() {
            return None;
        }
        words.get(hook + 2)?.clone()
    } else {
        if hook + 2 != words.len() {
            return None;
        }
        words.get(hook + 1)?.clone()
    };
    super::setup_hooks::EVENT_COMMANDS
        .iter()
        .any(|(_, expected)| *expected == label.as_str())
        .then_some(label)
}

fn managed_prefix(prefix: &[String]) -> bool {
    match prefix {
        [] => true,
        [profile] => is_profile_assignment(profile),
        [profile, project] => {
            is_profile_assignment(profile) && project.starts_with("HIBOSS_PROJECT_DIR=")
        }
        _ => false,
    }
}

fn is_profile_assignment(value: &str) -> bool {
    matches!(value, "HIBOSS_PROFILE=claude" | "HIBOSS_PROFILE=codex")
}

fn is_hiboss_executable(value: &str) -> bool {
    value == "hiboss"
        || (Path::new(value).is_absolute()
            && Path::new(value)
                .file_name()
                .is_some_and(|name| name.to_str() == Some("hiboss")))
}

fn shell_words(command: &str) -> Option<Vec<String>> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut quoted = None;
    let mut escaped = false;
    for character in command.chars() {
        if escaped {
            word.push(character);
            escaped = false;
            continue;
        }
        if let Some(quote) = quoted {
            if character == quote {
                quoted = None;
            } else {
                word.push(character);
            }
            continue;
        }
        match character {
            '\\' => escaped = true,
            '\'' | '"' => quoted = Some(character),
            character if character.is_whitespace() => {
                if !word.is_empty() {
                    words.push(std::mem::take(&mut word));
                }
            }
            _ => word.push(character),
        }
    }
    if escaped || quoted.is_some() {
        return None;
    }
    if !word.is_empty() {
        words.push(word);
    }
    Some(words)
}

fn shell_escape(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}
