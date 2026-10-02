// Purpose: Synthetic HTTP/1.1 server on 127.0.0.1 that records every request line.
// Exports: Loopback (start, url, requests). Serves one canned response per request;
// `requests` stops and joins the server after draining every earlier connection.
// Dependencies: std::net, std::thread, std::sync only.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

type Log = Arc<Mutex<Vec<String>>>;

/// Sent by `stop` on a fresh connection; never a valid HTTP request line.
const STOP_MARKER: &str = "LOOPBACK-STOP\r\n";
/// Bounds how long one stalled connection can hold up shutdown.
const READ_TIMEOUT: Duration = Duration::from_secs(5);

pub struct Loopback {
    port: u16,
    log: Log,
    worker: Option<JoinHandle<()>>,
}

enum Served {
    Continue,
    Stop,
}

impl Loopback {
    /// Answers every request with `status` and the JSON `body`, then closes the connection.
    pub fn start(status: u16, body: &str) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let port = listener.local_addr().expect("local addr").port();
        let log: Log = Arc::default();
        let (thread_log, response) = (log.clone(), response(status, body));
        let worker = thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                if let Served::Stop = serve(stream, &thread_log, &response) {
                    break;
                }
            }
        });
        Loopback { port, log, worker: Some(worker) }
    }

    pub fn url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    /// Request lines as `METHOD /path`, in arrival order. Call after the client exits:
    /// connections are accepted in order, so every one opened before the stop marker
    /// is served and logged before the worker is joined.
    pub fn requests(mut self) -> Vec<String> {
        self.stop();
        self.log.lock().expect("request log").clone()
    }

    fn stop(&mut self) {
        let Some(worker) = self.worker.take() else { return };
        if let Ok(mut stream) = TcpStream::connect(("127.0.0.1", self.port)) {
            let _ = stream.write_all(STOP_MARKER.as_bytes());
            let _ = worker.join();
        }
    }
}

impl Drop for Loopback {
    fn drop(&mut self) {
        self.stop();
    }
}

fn response(status: u16, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} Synthetic\r\nContent-Type: application/json\r\n\
         Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
}

fn serve(stream: TcpStream, log: &Log, response: &str) -> Served {
    let _ = stream.set_read_timeout(Some(READ_TIMEOUT));
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    if reader.read_line(&mut line).unwrap_or(0) == 0 {
        return Served::Continue;
    }
    if line == STOP_MARKER {
        return Served::Stop;
    }
    let mut length = 0usize;
    let mut header = String::new();
    while reader.read_line(&mut header).unwrap_or(0) > 2 {
        let lower = header.to_ascii_lowercase();
        if let Some(value) = lower.strip_prefix("content-length:") {
            length = value.trim().parse().unwrap_or(0);
        }
        header.clear();
    }
    let mut body = vec![0; length];
    let _ = reader.read_exact(&mut body);
    let request: Vec<&str> = line.split_whitespace().take(2).collect();
    log.lock().expect("request log").push(request.join(" "));
    let _ = reader.get_mut().write_all(response.as_bytes());
    Served::Continue
}
