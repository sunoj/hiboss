// Isolated git checkouts, HOME and config for session-identity tests of the built binary.
// Exports Fixture, Run, fnv, leaf, write_private and wait_until; the mock server comes from
// onboarding_support/http.rs. Dependencies: git, kill and ps on PATH, std::process, std::fs.

#![allow(dead_code)]
#[path = "../onboarding_support/http.rs"]
pub mod http;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicUsize = AtomicUsize::new(0);

pub struct Run {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// A sandbox holding a git repository, its HOME and a two-profile config.
pub struct Fixture {
    pub root: PathBuf,
    pub repo: PathBuf,
}

impl Fixture {
    pub fn new(repo_name: &str, server: &str) -> Self {
        let id = NEXT.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!("hiboss-sid-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let repo = root.join(repo_name);
        fs::create_dir_all(&repo).expect("repo dir");
        let fixture = Self { root, repo };
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

    /// Where `dirs::cache_dir` puts `hiboss/sessions` under the sandbox HOME.
    pub fn sessions_root(&self) -> PathBuf {
        let cache = if cfg!(target_os = "macos") { "Library/Caches" } else { ".cache" };
        self.root.join(cache).join("hiboss/sessions")
    }

    pub fn state_dir(&self, profile: &str, session: &str) -> PathBuf {
        self.sessions_root().join(self.project_key()).join(leaf(profile, session))
    }

    /// Creates this session's private state directory ahead of the CLI and returns it.
    pub fn prepare(&self, profile: &str, session: &str) -> PathBuf {
        let dir = self.state_dir(profile, session);
        private_dirs(&dir);
        dir
    }

    /// Every daemon pid file the CLI left in this sandbox, with its pid.
    pub fn daemon_pids(&self) -> Vec<u32> {
        let projects = fs::read_dir(self.sessions_root()).into_iter().flatten().flatten();
        let leaves = projects.flat_map(|project| fs::read_dir(project.path()).into_iter().flatten().flatten());
        leaves
            .filter_map(|leaf| fs::read_to_string(leaf.path().join("daemon.pid")).ok())
            .filter_map(|pid| pid.trim().parse().ok())
            .collect()
    }

    pub fn run(&self, dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Run {
        let output = Command::new(env!("CARGO_BIN_EXE_hiboss"))
            .args(args)
            .current_dir(dir)
            .env_clear()
            .env("HOME", &self.root)
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
    /// Stops the daemons this sandbox's CLI runs started, by the pid each one recorded.
    fn drop(&mut self) {
        for pid in self.daemon_pids() {
            if is_hiboss(pid) {
                let _ = Command::new("kill").arg(pid.to_string()).status();
            }
        }
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// True while `pid` is a live (not zombie) hiboss process; guards against a reused pid.
pub fn is_hiboss(pid: u32) -> bool {
    let Ok(out) = Command::new("ps").args(["-p", &pid.to_string(), "-o", "stat=,comm="]).output() else {
        return false;
    };
    let line = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    !line.starts_with('Z') && line.contains("hiboss")
}

/// The leaf directory name the CLI derives for (profile, session): hex of each, joined by `-`.
pub fn leaf(profile: &str, session: &str) -> String {
    let hex = |value: &str| value.bytes().map(|byte| format!("{byte:02x}")).collect::<String>();
    format!("{}-{}", hex(profile), hex(session))
}

/// Writes a state file the way the CLI does: owner-only 0600.
pub fn write_private(path: &Path, content: &str) {
    use std::os::unix::fs::PermissionsExt;
    fs::write(path, content).expect("state file");
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).expect("chmod state file");
}

/// Polls `check` for up to ten seconds.
pub fn wait_until(mut check: impl FnMut() -> bool) -> bool {
    let deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < deadline {
        if check() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    check()
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
