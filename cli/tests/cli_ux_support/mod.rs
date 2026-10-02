// Purpose: Run the hiboss binary under an isolated synthetic HOME for executable-level tests.
// Exports: Sandbox (config states, run), Outcome.
// Dependencies: std::process, std::fs; CARGO_BIN_EXE_hiboss from Cargo.

use std::fs;
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
        let output = Command::new(env!("CARGO_BIN_EXE_hiboss"))
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
            .stdin(Stdio::null())
            .output()
            .expect("run hiboss binary");
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
