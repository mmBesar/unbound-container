#!/bin/bash
# unbound-container entrypoint
# Optionally refreshes root.hints before starting Unbound
# Root hints change rarely — updated every few months by IANA
set -euo pipefail

ROOT_HINTS="/var/lib/unbound/root.hints"
ROOT_HINTS_URL="https://www.internic.net/domain/named.root"

# Try to refresh root.hints — not fatal if it fails (use existing or package copy)
echo "[entrypoint] Refreshing root.hints..."
if curl -fsSL --max-time 10 "$ROOT_HINTS_URL" -o "${ROOT_HINTS}.tmp" 2>/dev/null; then
    mv "${ROOT_HINTS}.tmp" "$ROOT_HINTS"
    echo "[entrypoint] root.hints updated"
else
    echo "[entrypoint] Could not fetch root.hints — using existing copy"
    # Fall back to dns-root-data package copy if no existing file
    if [ ! -f "$ROOT_HINTS" ]; then
        cp /usr/share/dns/root.hints "$ROOT_HINTS" 2>/dev/null || \
        cp /usr/share/unbound/root.hints "$ROOT_HINTS" 2>/dev/null || \
        echo "[entrypoint] WARNING: no root.hints found"
    fi
fi

# Validate config before starting
echo "[entrypoint] Validating configuration..."
unbound-checkconf /etc/unbound/unbound.conf

echo "[entrypoint] Starting Unbound..."
exec unbound -d -c /etc/unbound/unbound.conf
