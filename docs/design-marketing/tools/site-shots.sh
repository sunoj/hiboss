#!/bin/bash
# Convert raw iPhone demo captures (capture.sh output) into the site's 600 px JPEG screenshots.
# Usage: site-shots.sh <raw-iphone-capture-dir>   (run from the repository root)
# panels-* and mac-island-* are not produced here; see site/README.md.
set -euo pipefail
RAW=$1; OUT=site/assets/shots
for theme in light dark; do
  for pair in home:today decision:decision session:session sessions:sessions box:box progress:progress allclear:allclear; do
    name=${pair%%:*}; scene=${pair##*:}
    sips -s format jpeg -s formatOptions 82 --resampleWidth 600 "$RAW/$scene-en-$theme.png" \
      --out "$OUT/$name-$theme.jpg" >/dev/null
    sips -s format jpeg -s formatOptions 82 --resampleWidth 600 "$RAW/$scene-zh-$theme.png" \
      --out "$OUT/$name-zh-$theme.jpg" >/dev/null
  done
done
ls -l "$OUT" | awk '$5 > 400000 { print "too large:", $9; bad = 1 } END { exit bad }'
