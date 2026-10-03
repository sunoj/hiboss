// Purpose: Run the hiboss binary under an isolated synthetic HOME for executable-level tests.
// Exports: Sandbox (config states, run, run_loopback), Outcome.
// Dependencies: std::process, std::fs; CARGO_BIN_EXE_hiboss from Cargo.

use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

pub struct Outcome {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// A throwaway HOME; the config file lives where `dirs::config_dir` resolves it.
pub struct Sandbox {
    pub home: PathBuf,
}

impl Sandbox {
    pub fn new() -> Self {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let home = std::env::temp_dir().join(format!("hiboss-ux-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&home);
        fs::create_dir_all(&home).expect("create sandbox home");
        Sandbox { home }
    }

    fn config_dir(&self) -> PathBuf {
        if cfg!(target_os = "macos") {
            self.home.join("Library").join("Application Support")
        } else {
            self.home.join(".config")
        }
    }

    pub fn config_file(&self) -> PathBuf {
        self.config_dir().join("hiboss").join("config.json")
    }

    pub fn write_config(&self, body: &str) {
        let path = self.config_file();
        fs::create_dir_all(path.parent().expect("config parent")).expect("create config dir");
        fs::write(path, body).expect("write config");
    }

    pub fn read_config(&self) -> String {
        fs::read_to_string(self.config_file()).expect("read config")
    }

    pub fn run(&self, args: &[&str]) -> Outcome {
        self.execute(args, &[])
    }

    /// Like `run`, but 127.0.0.1 bypasses the dead proxy so a synthetic loopback server
    /// is reachable; every other host still fails fast.
    #[allow(dead_code)]
    pub fn run_loopback(&self, args: &[&str]) -> Outcome {
        self.execute(args, &[("NO_PROXY", "127.0.0.1")])
    }

    /// Drives interactive onboarding with a bounded process lifetime and synthetic input.
    #[allow(dead_code)]
    pub fn run_input(&self, args: &[&str], input: &str, extra: &[(&str, &str)]) -> Outcome {
        let mut command = self.command(args, extra);
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn hiboss");
        child
            .stdin
            .take()
            .expect("stdin")
            .write_all(input.as_bytes())
            .expect("write input");
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(20);
        while child.try_wait().expect("child status").is_none() {
            if std::time::Instant::now() >= deadline {
                child.kill().expect("stop stalled hiboss");
                let _ = child.wait();
                panic!("hiboss exceeded the 20-second test deadline");
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        Self::outcome(child.wait_with_output().expect("hiboss output"))
    }

    fn execute(&self, args: &[&str], extra: &[(&str, &str)]) -> Outcome {
        let output = self
            .command(args, extra)
            .stdin(Stdio::null())
            .output()
            .expect("run hiboss binary");
        Self::outcome(output)
    }

    fn command(&self, args: &[&str], extra: &[(&str, &str)]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_hiboss"));
        command
            .args(args)
            .current_dir(&self.home)
            .env_clear()
            .env("HOME", &self.home)
            .env("XDG_CONFIG_HOME", self.config_dir())
            .env("PATH", std::env::var("PATH").unwrap_or_default())
            .env("NO_COLOR", "1")
            // Any accidental HTTP request fails fast instead of leaving the box.
            .env("HTTPS_PROXY", "http://127.0.0.1:9")
            .env("HTTP_PROXY", "http://127.0.0.1:9")
            .envs(extra.iter().copied());
        command
    }

    fn outcome(output: std::process::Output) -> Outcome {
        Outcome {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        }
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.home);
    }
}
