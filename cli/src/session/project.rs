// Resolves one project identity for hooks, session labels, and progress posts.
// Exports ProjectIdentity and resolve_project; depends on git, environment, serde.
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct ProjectIdentity {
    pub slug: String,
    pub aliases: Vec<String>,
}

pub fn resolve_project(explicit: Option<&str>) -> ProjectIdentity {
    let directory = super::project_dir();
    let origin = std::process::Command::new("git")
        .args(["-C", &directory, "remote", "get-url", "origin"])
        .output().ok().filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned());
    identity(origin.as_deref(), &directory, std::env::var("HIBOSS_PROJECT").ok().as_deref(), explicit)
}

fn identity(origin: Option<&str>, directory: &str, override_alias: Option<&str>, explicit: Option<&str>) -> ProjectIdentity {
    let cwd = Path::new(directory).file_name().and_then(|name| name.to_str()).unwrap_or("project");
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
        let before = identity(Some("git@github.com:org/Repo.git"), "/work/old", None, None);
        let after = identity(Some("https://github.com/org/Repo.git/"), "/work/new", Some("override"), None);
        assert_eq!(before.slug, after.slug);
        assert_eq!(after.slug, "repo");
        assert_eq!(after.aliases, ["Repo", "new", "override"]);
    }

    #[test]
    fn explicit_project_becomes_slug_and_alias_without_losing_checkout() {
        let project = identity(Some("ssh://git@host/org/repo.git"), "/work/checkout", Some("env"), Some("My Project"));
        assert_eq!(project.slug, "my-project");
        assert_eq!(project.aliases, ["repo", "checkout", "env", "My Project"]);
        assert_eq!(serde_json::to_value(&project).unwrap()["slug"], "my-project");
    }

    #[test]
    fn no_origin_uses_directory_and_ignores_empty_overrides() {
        assert_eq!(identity(None, "/work/My Checkout", Some(" "), None),
            ProjectIdentity { slug: "my-checkout".into(), aliases: vec!["My Checkout".into()] });
    }

    #[test]
    fn handles_scp_origin_and_deduplicates_aliases() {
        let project = identity(Some("host:repo.git"), "/work/repo", Some("repo"), Some("repo"));
        assert_eq!(project.aliases, ["repo"]);
        assert_eq!(project.slug, "repo");
    }
}
