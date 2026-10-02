// Purpose: Synthetic HTTP/1.1 server on 127.0.0.1 that records every request line.
// Exports: Loopback (start, url, requests). Serves one canned response per request.
// Dependencies: std::net, std::thread, std::sync only.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;

type Log = Arc<Mutex<Vec<String>>>;

pub struct Loopback {
    port: u16,
    log: Log,
}

impl Loopback {
    /// Answers every request with `status` and the JSON `body`, then closes the connection.
    pub fn start(status: u16, body: &str) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let port = listener.local_addr().expect("local addr").port();
        let log: Log = Arc::default();
        let (thread_log, response) = (log.clone(), response(status, body));
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                serve(stream, &thread_log, &response);
            }
        });
        Loopback { port, log }
    }

    pub fn url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    /// Request lines as `METHOD /path`, in arrival order.
    pub fn requests(&self) -> Vec<String> {
        self.log.lock().expect("request log").clone()
    }
}

fn response(status: u16, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} Synthetic\r\nContent-Type: application/json\r\n\
         Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
}

fn serve(stream: TcpStream, log: &Log, response: &str) {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    if reader.read_line(&mut line).unwrap_or(0) == 0 {
        return;
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
}
