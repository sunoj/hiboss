#!/bin/sh
# Compare fresh migration/schema SQLite databases, or emit a regeneration patch.
# Entrypoint for npm and Vitest; requires Python 3.10+ with SQLite 3.35+.
set -eu
exec python3 -B "$(dirname "$0")/schema.py" "$@"
