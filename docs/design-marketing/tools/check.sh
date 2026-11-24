#!/bin/bash
# Verify the marketing deliverables: site tests, image budgets, no off-site resources, frame sizes.
# Usage: docs/design-marketing/tools/check.sh   (run from the repository root; compiles nothing)
set -euo pipefail
fail=0
note() { echo "FAIL: $*"; fail=1; }

python3 -B site/test_build.py 2>&1 | tail -n 3
out=$(mktemp -d)/public
bash site/build.sh "$out" >/dev/null

# Every published image stays under 400 KB.
while read -r file; do
  size=$(stat -f %z "$file")
  (( size < 400000 )) || note "$file is $size bytes"
done < <(find "$out" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.svg' \))

# No stylesheet, script, image or font is loaded from another origin, and no cookie is set.
if grep -rEn '(src|srcset)="(https?:)?//|<link[^>]+rel="(stylesheet|preload|preconnect)"[^>]+href="(https?:)?//|@import|url\((https?:)?//' \
    "$out" --include='*.html' --include='*.css' --include='*.js'; then note 'off-site resource'; fi
if grep -rn 'document.cookie' "$out" --include='*.html' --include='*.js'; then note 'cookie access'; fi

# The App Store switch stays one replaceable line on both download pages.
for page in download/index.html zh/download/index.html; do
  [[ $(grep -c 'APP STORE SWITCH' "site/$page") == 1 && $(grep -cE 'class="store-(soon|badge)' "site/$page") == 2 ]] \
    || note "App Store switch in $page"
done

# Store frames: exact size, no alpha. Promo cards: exact size.
store=docs/design-marketing/app-store
check_size() { # file width height
  local facts
  facts=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$1" | awk 'NR > 1 { printf "%s ", $2 }')
  [[ $facts == "$2 $3 no " ]] || note "$1 is $facts"
}
for locale in en-US zh-Hans; do
  iphone=("$store/$locale/iphone-6.9"/*.jpg); ipad=("$store/$locale/ipad-13"/*.jpg)
  (( ${#iphone[@]} >= 5 && ${#ipad[@]} >= 5 )) || note "$locale has too few frames"
  for file in "${iphone[@]}"; do check_size "$file" 1320 2868; done
  for file in "${ipad[@]}"; do check_size "$file" 2064 2752; done
done
for lang in en zh; do
  check_size "docs/design-marketing/promo/og-$lang.jpg" 1200 630
  check_size "docs/design-marketing/promo/square-$lang.jpg" 1080 1080
done
cmp -s docs/design-marketing/promo/og-en.jpg site/assets/og.jpg || note 'site og.jpg differs from promo/og-en.jpg'

python3 docs/design-marketing/tools/listing.py
git diff --quiet -- docs/design-marketing/app-store/listing.md ios/AppStore/metadata || note 'listing copy is stale'
# The listing folder holds exactly the composed frames, and no keyword names a third-party product.
diff -rq "$store/en-US" ios/AppStore/Screenshots/en-US >/dev/null && diff -rq "$store/zh-Hans" ios/AppStore/Screenshots/zh-Hans >/dev/null \
  || note 'ios/AppStore/Screenshots differs from the composed frames'
if grep -rniE 'claude|codex' ios/AppStore/metadata/*/keywords.txt; then note 'third-party name in keywords'; fi
(( fail == 0 )) && echo 'marketing checks passed'
exit $fail
