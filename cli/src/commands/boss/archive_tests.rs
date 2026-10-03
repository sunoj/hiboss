// Archive CLI tests for parsing, output, dates, HTTP paths, and API error propagation.
// Uses a loopback mock HTTP server and in-memory output; no external services.
use super::*;
use clap::Parser;
use std::{io::Read, net::TcpListener, thread};

#[derive(Parser)]
struct Args { #[command(flatten)] boss: crate::commands::boss::BossArgs }

fn mock(action: &str, status: u16, body: &str) -> (HiBossClient, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let client = HiBossClient::new(&format!("http://{}", listener.local_addr().expect("address")), "boss-test-token");
    let action = action.to_owned();
    let body = body.to_owned();
    let server = thread::spawn(move || {
        let (mut socket, _) = listener.accept().expect("request");
        socket.set_read_timeout(Some(std::time::Duration::from_secs(5))).expect("timeout");
        let mut request = Vec::new();
        let mut byte = [0];
        while !request.ends_with(b"\r\n\r\n") { socket.read_exact(&mut byte).expect("read"); request.push(byte[0]); }
        let request = String::from_utf8(request).expect("utf8");
        assert!(request.starts_with(&format!("POST /api/bosses/boss-id/{action} HTTP/1.1")));
        assert!(request.to_lowercase().contains("authorization: bearer boss-test-token"));
        write!(socket, "HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).expect("response");
    });
    (client, server)
}

#[tokio::test]
async fn parses_commands_and_prints_confirmed_archive_restore_output() {
    for (action, archived, expected) in [("archive", true, "Boss archived\n"), ("restore", false, "Boss restored\n")] {
        let args = Args::try_parse_from(["boss", action, "boss-id"]).expect("parse command");
        match args.boss.command {
            crate::commands::boss::BossCommand::Archive(id) => { assert!(archived); assert_eq!(id.id, "boss-id"); }
            crate::commands::boss::BossCommand::Restore(id) => { assert!(!archived); assert_eq!(id.id, "boss-id"); }
            _ => panic!("wrong command"),
        }
        let (client, server) = mock(action, 200, "{}");
        let mut output = Vec::new();
        run(&client, "boss-id", archived, &mut output).await.expect("success");
        assert_eq!(String::from_utf8(output).expect("utf8"), expected);
        server.join().expect("server");
    }
    assert!(Args::try_parse_from(["boss", "archive"]).is_err());
    assert!(Args::try_parse_from(["boss", "restore"]).is_err());
}

#[tokio::test]
async fn preserves_api_error_codes_and_messages_without_success_output() {
    for archive in [true, false] {
        for (status, message) in [(400, "cannot archive self"), (401, "unauthorized"), (403, "admin required"), (404, "not found"), (409, "boss is archived")] {
            let body = serde_json::json!({"error": message}).to_string();
            let (client, server) = mock(if archive { "archive" } else { "restore" }, status, &body);
            let mut output = Vec::new();
            let error = run(&client, "boss-id", archive, &mut output).await.expect_err("API rejection").to_string();
            assert!(error.contains(&status.to_string()), "{error}");
            assert!(error.contains(message), "{error}");
            assert!(output.is_empty());
            server.join().expect("server");
        }
    }
}

#[test]
fn list_displays_archive_date_or_dash() {
    assert_eq!(archived_date(&serde_json::json!({"archived_at": "2026-09-13 12:00:00"})), "2026-09-13");
    assert_eq!(archived_date(&serde_json::json!({"archived_at": null})), "-");
}
