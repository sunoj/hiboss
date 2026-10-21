#!/usr/bin/env bash
# Assemble the public HiBoss site from an explicit file list.
# The output contains only static files served by the hosting provider.
set -euo pipefail

if [[ $# -ne 1 || $1 != /* || -e $1 ]]; then
  echo "usage: $0 /absolute/new/output-directory" >&2
  exit 2
fi

source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
output_dir=$1

files=(
  index.html robots.txt sitemap.xml
  download/index.html changelog/index.html privacy/index.html support/index.html
  docs/self-host/index.html docs/agents/index.html
  zh/index.html zh/download/index.html zh/docs/self-host/index.html
  assets/site.css assets/icon.png assets/apple-touch-icon.png assets/og.jpg
)
for screen in home session panels progress box; do
  files+=("assets/shots/$screen-light.jpg" "assets/shots/$screen-dark.jpg")
done

for file in "${files[@]}"; do
  mkdir -p -- "$output_dir/$(dirname -- "$file")"
  cp -- "$source_dir/$file" "$output_dir/$file"
done
echo "$output_dir"
