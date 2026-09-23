# Public-release history cleanup

The repository was already public when this cleanup began. Removing a value from
Git history does not revoke credentials or remove copies held by existing clones.

## Scope

- Preserve project history, branches, tags, licensing, and contributor attribution.
- Remove historical local Worker configuration, temporary SQLite databases,
  generated orchestration state, scratch audit results, and private capture files.
- Replace a historical terminal boss credential and Wi-Fi configuration values
  with inert placeholders throughout history.
- Replace personal home directories, a private network address, and a deployment
  hostname with examples. Map the maintainer's private/local commit addresses to
  the existing GitHub noreply identity; preserve GitHub's commit attribution.
- Keep normal product demo screenshots and app icons. Local OCR inspected 44
  historical screenshots; six private/system-prompt captures were removed.
- Add `.gitleaks.toml` with default detection, HiBoss bearer/Wi-Fi rules, and only
  exact reviewed fixture exceptions. Do not exclude entire test directories.

The maintainer confirmed that the historical boss credential was revoked or
rotated. That is an operator attestation, not an independent live verification.
Wi-Fi credential status was not independently verified.

## Verification

Before rewriting, private backups were made outside the repository, including
Git bundles, the original Git metadata, working files, and reference inventories.
Raw scan reports and replacement mappings stay outside Git because they contain
the material being removed. Do not publish those backups or mapping files.

Use Gitleaks 8.30.1 with the repository configuration:

```sh
gitleaks git --log-opts=--all --redact
gitleaks dir --redact
```

The directory scan should target an exported tracked tree, not local ignored
dependencies or operator configuration. In addition to the default scan, validate
all reachable blobs and commit/tag metadata against the private removal manifest,
confirm removed paths are absent from every ref, and run `git fsck --full`.
Check both branches and tags, including imported PR heads used for the audit.

The pre-cleanup pending CLI/MCP changes were committed after 236 Rust tests and
10 MCP tests passed. The prior security batch passed 302 server tests and server
TypeScript checking. History rewriting changes commit IDs and invalidates commit
or tag signatures; old SHA references in historical documents describe the
pre-cleanup baseline and are not public recovery links.

Completed local verification:

- Removed 26 historical paths and retained 784 reachable commits after pruning
  empty cleanup-only commits. Local audit refs cover 19 imported PR heads.
- Gitleaks history scan and exported tracked-tree scan both returned zero findings
  under the checked-in configuration.
- An independent scan of reachable blobs and commit/tag metadata found zero
  occurrences of the private replacement values; removed paths were absent from
  every local ref. `git fsck --full` reported no problems or dangling objects.
- The current tree ID was identical before and immediately after rewriting.
- Commit author/committer identities now use the existing maintainer noreply
  address or GitHub's own noreply address.

The captured remote inventory contains 15 branch heads and 43 tags. Six additional
local historical branches came from stale tracking refs and must not be recreated
remotely merely because they were included in the local audit.

## Remote completion

The maintainer approved the remote rewrite. All 15 branch heads and 43 tags were
updated in one atomic, per-reference lease-protected push and compared against
the cleaned local refs: all 58 matched. A new bare repository fetched only those
GitHub branch/tag refs; its Gitleaks scan returned zero findings and Git object
integrity checks passed. No Releases or Actions artifacts were present when checked.

GitHub still advertised 19 PR heads pointing to the original history after that
push. Their cleanup is outstanding. A private support-request draft was prepared
outside this repository and has not been sent. This result certifies the rewritten
branch/tag histories, not complete erasure of every GitHub-hosted copy.

Local cleanup alone does not replace GitHub's history. Remote branch and tag
updates must use the captured old object IDs as force-with-lease expectations so
concurrent work is not overwritten. Avoid an unrestricted mirror push that could
delete unrelated remote refs. Other contributors should clone the cleaned history
again rather than merge or push an old clone back into it.

GitHub PR refs and cached commit views may retain old data and cannot all be
overwritten through a normal Git push. Follow GitHub's sensitive-data removal
process for those references and inspect release assets, Actions artifacts, and
external clones separately. A passing local scanner does not certify their removal.

References: [GitHub sensitive-data removal](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
and [git-filter-repo documentation](https://github.com/newren/git-filter-repo/blob/main/Documentation/git-filter-repo.txt).
