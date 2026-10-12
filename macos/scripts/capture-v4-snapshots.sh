#!/bin/sh
# Captures hosted v4 native windows in both appearances, including the notch card.
# Outputs PNG evidence to the supplied directory; requires Screen Recording access.
# Dependencies: SwiftPM, XCTest, caffeinate, and macOS screencapture.

set -eu
PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SNAPSHOT_DIR="${1:?Usage: capture-v4-snapshots.sh /absolute/output/directory}"
cd "$PACKAGE_DIR"
export HIBOSS_V4_SNAPSHOTS="$SNAPSHOT_DIR"
caffeinate -d -i -u -t 1800 /bin/sh -c 'swift test --filter TodaySnapshotTests'
for screen in today-decisions today-all-clear island session box progress menu-bar; do
    for appearance in light dark; do
        test -s "$SNAPSHOT_DIR/$screen-$appearance.png"
    done
done
