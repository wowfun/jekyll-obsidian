#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SITE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$SITE_DIR"
exec ruby "$SCRIPT_DIR/audit-site.rb" "${1:-_site}"
