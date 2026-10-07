// Purpose: Timeout-bounded loopback HTTP fixture for Box command tests.
// Exports: Mock, Reply and captured requests; depends only on tokio and std.
use std::{fs, path::PathBuf, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    task::JoinHandle,
};

pub(super) struct Reply {
    pub method: &'static str,
    pub path: &'static str,
    pub status: u16,
    pub body: String,
}

impl Reply {
    pub fn new(method: &'static str, path: &'static str, status: u16, body: String) -> Self {
        Self {
            method,
            path,
            status,
            body,
        }
    }
}

pub(super) struct Captured {
    pub headers: String,
    pub body: String,
}

pub(super) struct Mock {
    pub server: String,
    pub directory: PathBuf,
    task: JoinHandle<Vec<Captured>>,
}

impl Mock {
    pub async fn start(replies: Vec<Reply>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let directory =
            std::env::temp_dir().join(format!("hiboss-box-{}-{}", std::process::id(), address.port()));
        fs::create_dir_all(&directory).unwrap();
        let task = tokio::spawn(async move {
            let mut captured = Vec::new();
            for reply in replies {
                captured.push(
                    tokio::time::timeout(Duration::from_secs(10), serve(&listener, reply))
                        .await
                        .expect("expected Box HTTP request"),
                );
            }
            captured
        });
        Self {
            server: format!("http://{address}"),
            directory,
            task,
        }
    }

    pub async fn finish(self) -> Vec<Captured> {
        let result = self.task.await.expect("mock requests passed");
        fs::remove_dir_all(self.directory).unwrap();
        result
    }
}

async fn serve(listener: &TcpListener, reply: Reply) -> Captured {
    let (mut socket, _) = listener.accept().await.unwrap();
    let mut bytes = Vec::new();
    let mut byte = [0u8; 1];
    while !bytes.ends_with(b"\r\n\r\n") {
        socket.read_exact(&mut byte).await.unwrap();
        bytes.push(byte[0]);
    }
    let headers = String::from_utf8(bytes).unwrap();
    assert!(
        headers.starts_with(&format!("{} {} HTTP/1.1", reply.method, reply.path)),
        "unexpected route"
    );
    assert!(
        headers
            .to_ascii_lowercase()
            .contains("authorization: bearer synthetic-box-key")
    );
    let length = headers
        .lines()
        .find_map(|line| {
            line.to_ascii_lowercase()
                .strip_prefix("content-length: ")
                .and_then(|value| value.parse::<usize>().ok())
        })
        .unwrap_or(0);
    let mut body = vec![0; length];
    socket.read_exact(&mut body).await.unwrap();
    let response = format!(
        "HTTP/1.1 {} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\
        Connection: close\r\n\r\n{}",
        reply.status,
        reply.body.len(),
        reply.body
    );
    socket.write_all(response.as_bytes()).await.unwrap();
    Captured {
        headers,
        body: String::from_utf8(body).unwrap(),
    }
}
