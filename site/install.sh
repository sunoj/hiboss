#!/bin/sh
# Download a prebuilt HiBoss CLI and verify its release checksum.
# Requires curl, tar, and sha256sum or shasum; never invokes sudo.
set -eu

fail() { echo "hiboss installer: $*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || fail 'curl is required'
case $(uname -s) in
    Darwin) os=apple-darwin ;;
    Linux) os=unknown-linux-musl ;;
    *) fail 'unsupported operating system' ;;
esac
case $(uname -m) in
    arm64|aarch64) arch=aarch64 ;;
    x86_64|amd64) arch=x86_64 ;;
    *) fail 'unsupported architecture' ;;
esac
version=${HIBOSS_VERSION:-}
if [ -z "$version" ]; then
    # Query the CLI tag namespace, independent of other product releases.
    version=$(curl -fsSL 'https://api.github.com/repos/sunoj/hiboss/releases?per_page=100' |
        tr '\n' ' ' | sed 's/"tag_name"/\n"tag_name"/g' |
        sed -n 's/^"tag_name"[[:space:]]*:[[:space:]]*"cli-v\([0-9][0-9.]*\)".*/\1/p' |
        head -n 1)
fi
version=${version#cli-v}
case $version in
    ''|*[!0-9.]*|.*|*.) fail 'invalid or missing CLI release version' ;;
esac
asset=hiboss-$version-$arch-$os.tar.gz
url=https://github.com/sunoj/hiboss/releases/download/cli-v$version
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
trap 'exit 1' HUP INT TERM
curl -fsSL "$url/$asset" -o "$work/$asset"
curl -fsSL "$url/$asset.sha256" -o "$work/checksum"
expected=$(awk 'NR == 1 { print $1 }' "$work/checksum")
[ "${#expected}" -eq 64 ] || fail 'invalid checksum'
case $expected in *[!0-9a-fA-F]*) fail 'invalid checksum' ;; esac
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$work/$asset" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$work/$asset" | awk '{print $1}')
else
    fail 'sha256sum or shasum is required'
fi
[ "$actual" = "$expected" ] || fail 'checksum mismatch'
tar -xzf "$work/$asset" -C "$work" hiboss
install_dir=${HIBOSS_INSTALL_DIR:-$HOME/.local/bin}
mkdir -p "$install_dir"
install -m 755 "$work/hiboss" "$install_dir/hiboss"
echo "Installed hiboss $version to $install_dir/hiboss"
echo "Ensure $install_dir is on PATH, then run: hiboss setup --server <server-url>"
