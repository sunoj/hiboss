// Isolated git checkouts, TMPDIR and config for session-identity tests of the built binary.
// Exports Fixture, Run and fnv; a mock server comes from onboarding_support/http.rs.
// Dependencies: git on PATH, std::process, std::fs.

#![allow(dead_code)]
#[path = "../onboarding_support/http.rs"]
pub mod http;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

pub struct Run {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// A sandbox holding a git repository, its TMPDIR and a two-profile config.
pub struct Fixture {
    pub root: PathBuf,
    pub repo: PathBuf,
    sleepers: Vec<Child>,
}

impl Fixture {
    pub fn new(repo_name: &str, server: &str) -> Self {
        let id = NEXT.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!("hiboss-sid-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let repo = root.join(repo_name);
        fs::create_dir_all(&repo).expect("repo dir");
        fs::create_dir_all(root.join("tmp")).expect("tmp dir");
        let fixture = Self {
            root,
            repo,
            sleepers: Vec::new(),
        };
        fixture.git(&fixture.repo, &["init", "-q", "-b", "main"]);
        fixture.git(
            &fixture.repo,
            &["commit", "-q", "--allow-empty", "-m", "init"],
        );
        let config = serde_json::json!({
            "version": 2, "server": server, "device_id": null, "default_profile": "claude",
            "channel": null,
            "profiles": {
                "claude": {"key": "synthetic-claude-key", "agent_id": "a1", "name": "u-claude@h", "server": null},
                "codex": {"key": "synthetic-codex-key", "agent_id": "a2", "name": "u-codex@h", "server": null}
            }
        });
        fs::write(fixture.config(), config.to_string()).expect("config");
        fixture
    }

    pub fn config(&self) -> PathBuf {
        self.root.join("config.json")
    }

    pub fn git(&self, dir: &Path, args: &[&str]) {
        let status = Command::new("git")
            .args(["-c", "user.name=t", "-c", "user.email=t@example.test"])
            .args(args)
            .current_dir(dir)
            .env("HOME", &self.root)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .expect("run git");
        assert!(status.success(), "git {args:?} failed");
    }

    /// Adds a worktree whose directory name has nothing in common with the repository.
    pub fn worktree(&self, name: &str) -> PathBuf {
        let path = self.root.join(name);
        self.git(
            &self.repo,
            &[
                "worktree",
                "add",
                "-q",
                "-b",
                name,
                path.to_str().expect("utf8"),
            ],
        );
        path
    }

    /// The project key the contract defines: FNV-1a of the canonical git common dir.
    pub fn project_key(&self) -> String {
        let common = fs::canonicalize(self.repo.join(".git")).expect("common dir");
        fnv(&common.to_string_lossy())
    }

    pub fn state_dir(&self, leaf: &str) -> PathBuf {
        self.root
            .join("tmp")
            .join("hiboss")
            .join(self.project_key())
            .join(leaf)
    }

    /// Creates a state directory whose daemon pid names a live sleeper, so no daemon starts.
    pub fn prepare(&mut self, leaf: &str) -> PathBuf {
        let dir = self.state_dir(leaf);
        private_dirs(&dir);
        let sleeper = Command::new("sleep").arg("60").spawn().expect("sleeper");
        fs::write(dir.join("daemon.pid"), sleeper.id().to_string()).expect("pid file");
        self.sleepers.push(sleeper);
        dir
    }

    pub fn run(&self, dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Run {
        let output = Command::new(env!("CARGO_BIN_EXE_hiboss"))
            .args(args)
            .current_dir(dir)
            .env_clear()
            .env("HOME", &self.root)
            .env("TMPDIR", self.root.join("tmp"))
            .env("HIBOSS_CONFIG", self.config())
            // git and kill only: an installed `hiboss` must not answer the hook's subprocesses.
            .env("PATH", "/usr/bin:/bin")
            .env("NO_COLOR", "1")
            .env("NO_PROXY", "127.0.0.1")
            .envs(env.iter().copied())
            .stdin(Stdio::null())
            .output()
            .expect("run hiboss");
        Run {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        for sleeper in &mut self.sleepers {
            let _ = sleeper.kill();
            let _ = sleeper.wait();
        }
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn private_dirs(dir: &Path) {
    use std::os::unix::fs::DirBuilderExt;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)
        .expect("state dir");
}

pub fn fnv(value: &str) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in value.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

pub fn read(path: &Path) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_owned()
}
