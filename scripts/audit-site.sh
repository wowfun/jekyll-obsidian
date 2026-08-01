#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec ruby "$SCRIPT_DIR/audit-site.rb" "${1:-_site}"
