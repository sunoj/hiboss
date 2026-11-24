#!/bin/bash
# Replace ios/AppStore/Screenshots with the composed frames, one folder per locale and device.
# Usage: docs/design-marketing/tools/store-screenshots.sh   (run from the repository root)
set -euo pipefail
SOURCE=docs/design-marketing/app-store
TARGET=ios/AppStore/Screenshots
rm -rf "$TARGET"
for locale in en-US zh-Hans; do
  for device in iphone-6.9 ipad-13; do
    mkdir -p "$TARGET/$locale/$device"
    cp "$SOURCE/$locale/$device"/*.jpg "$TARGET/$locale/$device/"
  done
done
find "$TARGET" -name '*.jpg' | wc -l | xargs echo "listing screenshots:"
