#!/bin/sh
# Exercise the installer against local release fixtures and a stub downloader.
# No network requests or Rust compilation are performed.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
mkdir -p "$work/bin" "$work/release" "$work/payload"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
set -eu
if [ "$2" = 'https://api.github.com/repos/sunoj/hiboss/releases?per_page=100' ]; then
    echo '[{"tag_name":"ios-v9"},{"tag_name":"cli-v1.13.0"}]'
else
    cp "$FIXTURES/${2##*/}" "$4"
fi
STUB
cat > "$work/bin/uname" <<'STUB'
#!/bin/sh
case $1 in -s) echo "$TEST_OS" ;; -m) echo "$TEST_ARCH" ;; esac
STUB
chmod +x "$work/bin/curl" "$work/bin/uname"
printf '#!/bin/sh\necho fake-hiboss\n' > "$work/payload/hiboss"
export FIXTURES="$work/release"
export PATH="$work/bin:$PATH"
for pair in Darwin:arm64 Darwin:x86_64 Linux:x86_64 Linux:aarch64; do
    TEST_OS=${pair%:*}; TEST_ARCH=${pair#*:}
    export TEST_OS TEST_ARCH
    case $TEST_OS in Darwin) os=apple-darwin ;; Linux) os=unknown-linux-musl ;; esac
    case $TEST_ARCH in arm64) arch=aarch64 ;; *) arch=$TEST_ARCH ;; esac
    asset=hiboss-1.13.0-$arch-$os.tar.gz
    tar -czf "$FIXTURES/$asset" -C "$work/payload" hiboss
    shasum -a 256 "$FIXTURES/$asset" > "$FIXTURES/$asset.sha256"
    HIBOSS_INSTALL_DIR="$work/install" sh "$root/scripts/install.sh" > "$work/output"
    test "$(sh "$work/install/hiboss")" = fake-hiboss
    grep -q 'hiboss setup --server' "$work/output"
    printf 'PASS install %s\n' "$pair"
done
HIBOSS_VERSION=cli-v1.13.0 HIBOSS_INSTALL_DIR="$work/pinned" sh "$root/scripts/install.sh"
test -x "$work/pinned/hiboss"
printf '%064d\n' 0 > "$FIXTURES/$asset.sha256"
if HIBOSS_VERSION=1.13.0 HIBOSS_INSTALL_DIR="$work/rejected" \
    sh "$root/scripts/install.sh" > "$work/output" 2>&1; then
    echo 'FAIL checksum mismatch accepted' >&2
    exit 1
fi
grep -q 'checksum mismatch' "$work/output"
test ! -e "$work/rejected/hiboss"
echo 'PASS checksum mismatch aborts before installation'
cmp "$root/scripts/install.sh" "$root/site/install.sh"
echo 'PASS site installer matches source'
