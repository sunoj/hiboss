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
mkdir -p -- "$output_dir/assets" "$output_dir/privacy" "$output_dir/support"
cp -- "$source_dir/index.html" "$source_dir/robots.txt" "$source_dir/sitemap.xml" "$output_dir/"
cp -- "$source_dir/privacy/index.html" "$output_dir/privacy/"
cp -- "$source_dir/support/index.html" "$output_dir/support/"
cp -- "$source_dir/assets/site.css" "$source_dir/assets/hiboss-iphone.jpg" \
  "$source_dir/assets/hiboss-icon.png" "$source_dir/assets/apple-touch-icon.png" "$output_dir/assets/"
echo "$output_dir"
