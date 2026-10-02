#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > MIGRATION.md <<'MD'
# Migrating from backup.sh v1 to v2

## Overview

v2 keeps the same job: archive a source directory. Four behaviors changed.

## Breaking changes

- The default archive directory is now ~/.local/share/backups (was ./out).
- The flag --output is renamed to --dest.
- bash 4.4 or newer is required (was 3.2).
- A missing source now exits with code 66 (was 1).

## Upgrade steps

1. Upgrade bash to 4.4 or newer.
2. Replace --output with --dest in your scripts.
3. Move existing archives from ./out to ~/.local/share/backups, or pass --dest ./out.
4. Treat exit code 66 as "source missing".
MD
