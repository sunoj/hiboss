// Purpose: Executable-level tests for root help, offline utilities and config recovery.
// Runs the real binary against missing, empty, malformed and partial config in a sandbox HOME;
// every remote-required case must fail before any HTTP request. Dependencies: cli_ux_support.

mod cli_ux_support;

use cli_ux_support::Sandbox;

const GROUPS: [&str; 6] = [
    "Get started:",
    "Talk to your boss:",
    "Show work:",
    "Coordinate sessions:",
    "Run in the background:",
    "Administer the server:",
];

#[test]
fn help_lists_grouped_commands_and_examples_on_stdout() {
    let out = Sandbox::new().run(&["--help"]);
    assert_eq!(out.code, 0, "stderr: {}", out.stderr);
    for group in GROUPS {
        assert!(
            out.stdout.contains(group),
            "missing {group} in:\n{}",
            out.stdout
        );
    }
    assert!(out.stdout.contains("Examples:\n  hiboss setup --server https://"));
    assert!(
        out.stdout.contains("  inbox "),
        "commands keep their descriptions"
    );
    assert!(out.stdout.contains("--version"));
    assert!(out.stderr.is_empty());
}

#[test]
fn bare_command_prints_grouped_help_to_stderr_with_usage_exit_code() {
    let out = Sandbox::new().run(&[]);
    assert_eq!(out.code, 2);
    assert!(out.stdout.is_empty());
    assert!(
        out.stderr.contains("Get started:"),
        "stderr: {}",
        out.stderr
    );
    assert!(out.stderr.contains("Examples:"));
}

#[test]
fn subcommand_help_keeps_the_default_layout() {
    let out = Sandbox::new().run(&["send", "--help"]);
    assert_eq!(out.code, 0);
    assert!(out.stdout.contains("Usage: hiboss send"));
    assert!(!out.stdout.contains("Get started:"));
}

#[test]
fn panel_guide_works_with_missing_empty_and_malformed_config() {
    for config in [None, Some(""), Some("{not json")] {
        let sandbox = Sandbox::new();
        if let Some(body) = config {
            sandbox.write_config(body);
        }
        let out = sandbox.run(&["panel", "guide"]);
        assert_eq!(out.code, 0, "config {config:?}: {}", out.stderr);
        assert!(
            out.stdout.len() > 200,
            "guide printed for config {config:?}"
        );
    }
}

const MINIMAL_PANEL: &str = r#"{"protocolVersion":2,"targetBossId":"boss_1","taskKey":"task_1",
"sessionId":"session_1","title":"Panel","catalogId":"hiboss.panel","catalogVersion":1,
"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done",
"value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object","properties":
{"task":{"type":"object","properties":{"done":{"type":"integer"}},"required":["done"],
"additionalProperties":false}},"required":["task"],"additionalProperties":false},
"initialState":{"task":{"done":0}}}"#;

#[test]
fn panel_validate_works_with_malformed_config() {
    let sandbox = Sandbox::new();
    sandbox.write_config("{not json");
    let file = sandbox.home.join("panel.json");
    std::fs::write(&file, MINIMAL_PANEL).expect("write panel");
    let out = sandbox.run(&["panel", "validate", file.to_str().expect("utf8 path")]);
    assert_eq!(out.code, 0, "stderr: {}", out.stderr);
    assert_eq!(out.stdout.trim(), "valid");
}

#[test]
fn remote_command_without_config_names_rule_four_and_server_recovery() {
    for config in [None, Some(""), Some("{}")] {
        let sandbox = Sandbox::new();
        if let Some(body) = config {
            sandbox.write_config(body);
        }
        let out = sandbox.run(&["panel", "list", "--json"]);
        assert_eq!(out.code, 3, "config {config:?}: {}", out.stderr);
        assert!(out.stdout.is_empty(), "JSON stdout stays clean");
        assert!(
            out.stderr.contains("server is not configured"),
            "{}",
            out.stderr
        );
        assert!(
            out.stderr.contains("rule 4") && out.stderr.contains("hiboss config set server <url>"),
            "{}",
            out.stderr
        );
        assert_eq!(
            out.stderr.lines().count(),
            1,
            "one recovery line: {}",
            out.stderr
        );
    }
}

#[test]
fn partial_config_names_the_missing_value() {
    let sandbox = Sandbox::new();
    sandbox.write_config(r#"{"key":"synthetic-test-key"}"#);
    let out = sandbox.run(&["send", "hello"]);
    assert_eq!(out.code, 3);
    assert!(
        out.stderr.contains("hiboss config set server <url>"),
        "{}",
        out.stderr
    );
    assert!(
        !out.stderr.contains("synthetic-test-key"),
        "never echo the key"
    );

    sandbox.write_config(r#"{"server":"https://hiboss.invalid"}"#);
    let out = sandbox.run(&["send", "hello"]);
    assert_eq!(out.code, 3);
    assert!(
        out.stderr.contains("hiboss setup --server <server-url> --profile"),
        "{}",
        out.stderr
    );
}

#[test]
fn malformed_config_names_the_file_and_one_recovery_step() {
    let sandbox = Sandbox::new();
    sandbox.write_config(r#"{"server": "https://hiboss.invalid", "key": "synthetic-test-key""#);
    let out = sandbox.run(&["send", "hello"]);
    assert_eq!(out.code, 1);
    assert!(out.stdout.is_empty());
    let path = sandbox.config_file().display().to_string();
    assert!(
        out.stderr
            .contains(&format!("config file {path} is not valid")),
        "{}",
        out.stderr
    );
    assert!(
        out.stderr.contains("move the file aside as a backup"),
        "{}",
        out.stderr
    );
    assert!(
        !out.stderr.contains("synthetic-test-key"),
        "never echo the key"
    );
}

#[test]
fn config_set_refuses_to_overwrite_malformed_config() {
    let sandbox = Sandbox::new();
    let broken = "{\"key\": \"synthetic-test-key\",";
    sandbox.write_config(broken);
    let out = sandbox.run(&["config", "set", "server", "https://hiboss.invalid"]);
    assert_eq!(out.code, 1);
    assert_eq!(
        sandbox.read_config(),
        broken,
        "the broken file is left for the user"
    );
}

#[test]
fn malformed_scalar_configuration_never_echoes_its_value() {
    let sandbox = Sandbox::new();
    sandbox.write_config(r#""synthetic-private-value""#);
    let out = sandbox.run(&["panel", "list", "--json"]);
    assert_eq!(out.code, 1);
    assert!(out.stdout.is_empty());
    assert!(out.stderr.contains("line 1, column"));
    assert!(!out.stderr.contains("synthetic-private-value"));
}

#[test]
fn config_commands_work_without_a_config_file() {
    let sandbox = Sandbox::new();
    let out = sandbox.run(&["config", "get", "server"]);
    assert_eq!((out.code, out.stdout.trim()), (0, "-"));
    let out = sandbox.run(&["config", "set", "server", "https://hiboss.invalid"]);
    assert_eq!(out.code, 0, "stderr: {}", out.stderr);
    let out = sandbox.run(&["config", "get", "server"]);
    assert_eq!(out.stdout.trim(), "https://hiboss.invalid");
}
