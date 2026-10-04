// Runs a synthetic HTTP server that captures onboarding requests in memory.
// Exports Http, Request, and Response for built-binary tests. A JSON string body is sent
// as raw text, the way the server answers with c.text().
// Dependencies: only std networking, synchronization, and threads.

use serde_json::Value;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub struct Request {
    pub method: String,
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub body: Value,
}

impl Request {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

pub struct Response {
    pub status: u16,
    pub body: Value,
    pub delay: Duration,
}

impl Response {
    pub fn json(status: u16, body: Value) -> Self {
        Self {
            status,
            body,
            delay: Duration::ZERO,
        }
    }
}

pub struct Http {
    pub url: String,
    requests: Arc<Mutex<Vec<Request>>>,
    stopping: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Http {
    pub fn start(handler: impl Fn(&Request) -> Response + Send + 'static) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock server");
        let url = format!("http://{}", listener.local_addr().expect("mock address"));
        let requests: Arc<Mutex<Vec<Request>>> = Arc::default();
        let log = requests.clone();
        let stopping: Arc<AtomicBool> = Arc::default();
        let stop = stopping.clone();
        let worker = thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let mut reader = BufReader::new(stream);
                // A client that hangs up without a request (a killed daemon) is skipped.
                let Some(request) = read_request(&mut reader) else {
                    match stop.load(Ordering::SeqCst) {
                        true => break,
                        false => continue,
                    }
                };
                let response = handler(&request);
                log.lock().expect("request log").push(request);
                thread::sleep(response.delay);
                let (kind, body) = match response.body {
                    Value::String(text) => ("text/plain", text),
                    body => ("application/json", body.to_string()),
                };
                let wire = format!(
                    "HTTP/1.1 {} Synthetic\r\nContent-Type: {kind}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    response.status,
                    body.len()
                );
                let _ = reader.get_mut().write_all(wire.as_bytes());
            }
        });
        Self {
            url,
            requests,
            stopping,
            worker: Some(worker),
        }
    }

    /// Paths requested so far, leaving the server running.
    pub fn paths(&self) -> Vec<String> {
        let log = self.requests.lock().expect("request log");
        log.iter().map(|request| format!("{} {}", request.method, request.path)).collect()
    }

    pub fn requests(mut self) -> Vec<Request> {
        self.stop();
        std::mem::take(&mut *self.requests.lock().expect("request log"))
    }

    fn stop(&mut self) {
        if let Some(worker) = self.worker.take() {
            self.stopping.store(true, Ordering::SeqCst);
            let address = self.url.trim_start_matches("http://");
            let mut stream = TcpStream::connect(address).expect("stop mock server");
            let _ = stream.write_all(b"STOP\r\n");
            worker.join().expect("mock worker");
        }
    }
}

impl Drop for Http {
    fn drop(&mut self) {
        self.stop();
    }
}

fn read_request(reader: &mut BufReader<TcpStream>) -> Option<Request> {
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_secs(3)))
        .ok()?;
    let mut first = String::new();
    reader.read_line(&mut first).ok()?;
    if first.trim() == "STOP" {
        return None;
    }
    let mut words = first.split_whitespace();
    let method = words.next()?.to_owned();
    let path = words.next()?.to_owned();
    let mut headers = Vec::new();
    let mut length = 0usize;
    loop {
        let mut line = String::new();
        reader.read_line(&mut line).ok()?;
        if line.trim().is_empty() {
            break;
        }
        let (name, value) = line.trim().split_once(':')?;
        if name.eq_ignore_ascii_case("content-length") {
            length = value.trim().parse().ok()?;
        }
        headers.push((name.to_ascii_lowercase(), value.trim().to_owned()));
    }
    let mut body = vec![0; length];
    reader.read_exact(&mut body).ok()?;
    Some(Request {
        method,
        path,
        headers,
        body: serde_json::from_slice(&body).unwrap_or(Value::Null),
    })
}
