#!/bin/bash
# Orchestrator: sources env + numbered modules (extend by adding modules/NN-name.sh).
set -euo pipefail

if [ "${EUID:-0}" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_PREVIEW="$(cd "$LINUX_DIR/.." && pwd)"
mkdir -p "$REPO_ROOT_PREVIEW/logs"
LOG_FILE="$REPO_ROOT_PREVIEW/logs/provision-$(date +%Y%m%d-%H%M%S).log"
# Full stdout/stderr to console and to timestamped log (for post-mortem errors).
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Uchet WSL provision log: $LOG_FILE ==="
echo "Started: $(date -Iseconds)  user: $(id -un 2>/dev/null || true)  host: $(uname -a 2>/dev/null || true)"

# Scripts on /mnt/c often have Windows CRLF and/or UTF-8 BOM; bash then errors on $'\r' or "﻿#".
normalize_script_for_wsl() {
    local f tmp hex
    f="$1"
    [ -f "$f" ] || return 0
    tmp=$(mktemp)
    tr -d '\r' <"$f" >"$tmp"
    if ! cmp -s "$f" "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
        echo "Provision: removed CR (CRLF) from $(basename "$f")" >&2
    else
        rm -f "$tmp"
    fi
    hex=$(head -c 3 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [ "$hex" = "efbbbf" ]; then
        tmp=$(mktemp)
        tail -c +4 "$f" >"$tmp" && mv "$tmp" "$f"
        echo "Provision: stripped UTF-8 BOM from $(basename "$f")" >&2
    fi
}
shopt -s nullglob
_norm_targets=("$LINUX_DIR/lib/00-env-and-credentials.sh")
_norm_targets+=("$LINUX_DIR"/modules/[0-9][0-9]-*.sh)
_norm_targets+=("$LINUX_DIR"/assets/*.sh)
for f in "${_norm_targets[@]}"; do
    [ -f "$f" ] || continue
    normalize_script_for_wsl "$f"
done

# shellcheck source=lib/00-env-and-credentials.sh
. "$LINUX_DIR/lib/00-env-and-credentials.sh"

shopt -s nullglob
for mod in "$LINUX_DIR"/modules/[0-9][0-9]-*.sh; do
    echo ">>> $(basename "$mod")"
    # shellcheck disable=SC1090
    . "$mod"
done

echo "=== PROVISION COMPLETE ==="
echo "Open: https://${WSL_DOMAIN:-localhost}/"
echo "Credentials: $CREDS_DIR"
echo "Full session log: $LOG_FILE"
