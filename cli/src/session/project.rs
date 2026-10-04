// Resolves one project identity for hooks, session labels, and progress posts.
// The name comes from the origin URL, else the repository itself; never a worktree directory.
// Exports ProjectIdentity and resolve_project; depends on git, environment, serde.
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Command;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct ProjectIdentity {
    pub slug: String,
    pub aliases: Vec<String>,
}

pub fn resolve_project(explicit: Option<&str>) -> ProjectIdentity {
    let directory = super::project_dir();
    let origin = Command::new("git")
        .args(["-C", &directory, "remote", "get-url", "origin"])
        .output().ok().filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned());
    // Named after the repository, so a worktree's own directory name never leaks in.
    let name = super::git_common_dir().and_then(|common| repository_name(&common, is_bare(&common)))
        .or_else(|| base_name(Path::new(&directory)))
        .unwrap_or_else(|| "project".to_owned());
    identity(origin.as_deref(), &name, std::env::var("HIBOSS_PROJECT").ok().as_deref(), explicit)
}

/// A checkout's `.git` is named by its parent; a bare repository by its own basename minus `.git`.
fn repository_name(common: &Path, bare: bool) -> Option<String> {
    let checkout = !bare && common.file_name().is_some_and(|name| name == ".git");
    let name = base_name(if checkout { common.parent()? } else { common })?;
    match name.strip_suffix(".git") {
        Some("") => base_name(common.parent()?),
        Some(stem) => Some(stem.to_owned()),
        None => Some(name),
    }
}

fn is_bare(common: &Path) -> bool {
    Command::new("git").arg("--git-dir").arg(common).args(["config", "--bool", "core.bare"])
        .output().ok().filter(|output| output.status.success())
        .is_some_and(|output| String::from_utf8_lossy(&output.stdout).trim() == "true")
}

fn base_name(path: &Path) -> Option<String> {
    path.file_name().and_then(|name| name.to_str()).map(str::to_owned)
}

fn identity(origin: Option<&str>, cwd: &str, override_alias: Option<&str>, explicit: Option<&str>) -> ProjectIdentity {
    let repo = origin.map(|url| url.trim_end_matches('/').trim_end_matches(".git"))
        .and_then(|url| url.rsplit(['/', ':']).next()).filter(|name| !name.is_empty());
    let explicit = explicit.filter(|name| !name.trim().is_empty());
    let slug = slugify(explicit.or(repo).unwrap_or(cwd));
    let mut aliases = Vec::new();
    for alias in [repo, Some(cwd), override_alias, explicit].into_iter().flatten() {
        if !alias.trim().is_empty() && !aliases.iter().any(|value| value == alias) {
            aliases.push(alias.to_owned());
        }
    }
    ProjectIdentity { slug, aliases }
}

fn slugify(value: &str) -> String {
    let mut slug = String::new();
    for ch in value.trim().chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' {
            slug.push(ch.to_ascii_lowercase());
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let slug = slug.trim_matches('-');
    if slug.is_empty() { "project".to_owned() } else { slug.to_owned() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renamed_checkout_retains_origin_slug_and_both_names() {
        let before = identity(Some("git@github.com:org/Repo.git"), "old", None, None);
        let after = identity(Some("https://github.com/org/Repo.git/"), "new", Some("override"), None);
        assert_eq!(before.slug, after.slug);
        assert_eq!(after.slug, "repo");
        assert_eq!(after.aliases, ["Repo", "new", "override"]);
    }

    #[test]
    fn explicit_project_becomes_slug_and_alias_without_losing_checkout() {
        let project = identity(Some("ssh://git@host/org/repo.git"), "checkout", Some("env"), Some("My Project"));
        assert_eq!(project.slug, "my-project");
        assert_eq!(project.aliases, ["repo", "checkout", "env", "My Project"]);
        assert_eq!(serde_json::to_value(&project).unwrap()["slug"], "my-project");
    }

    #[test]
    fn no_origin_uses_directory_and_ignores_empty_overrides() {
        assert_eq!(identity(None, "My Checkout", Some(" "), None),
            ProjectIdentity { slug: "my-checkout".into(), aliases: vec!["My Checkout".into()] });
    }

    #[test]
    fn handles_scp_origin_and_deduplicates_aliases() {
        let project = identity(Some("host:repo.git"), "repo", Some("repo"), Some("repo"));
        assert_eq!(project.aliases, ["repo"]);
        assert_eq!(project.slug, "repo");
    }

    #[test]
    fn bare_repository_is_named_by_its_own_directory() {
        assert_eq!(repository_name(Path::new("/work/alpha/.git"), false).as_deref(), Some("alpha"));
        assert_eq!(repository_name(Path::new("/work/alpha.git"), true).as_deref(), Some("alpha"));
        assert_eq!(repository_name(Path::new("/work/alpha.git"), false).as_deref(), Some("alpha"));
        assert_eq!(repository_name(Path::new("/work/beta/.git"), true).as_deref(), Some("beta"));
        assert_eq!(repository_name(Path::new("/work/gamma/.bare"), true).as_deref(), Some(".bare"));
    }
}
