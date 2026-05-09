#!/bin/bash
# unbound-container entrypoint
# Runs as root to refresh root.hints, then starts Unbound
# Unbound drops to the unbound user itself via its own config
set -euo pipefail

ROOT_HINTS="/var/lib/unbound/root.hints"
ROOT_HINTS_URL="https://www.internic.net/domain/named.root"

# Try to refresh root.hints — not fatal if it fails
echo "[entrypoint] Refreshing root.hints..."
if curl -fsSL --max-time 10 "$ROOT_HINTS_URL" -o "${ROOT_HINTS}.tmp" 2>/dev/null; then
    mv "${ROOT_HINTS}.tmp" "$ROOT_HINTS"
    chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || true
    echo "[entrypoint] root.hints updated"
else
    echo "[entrypoint] Could not fetch root.hints — using existing copy"
    if [ ! -f "$ROOT_HINTS" ]; then
        # Fall back to package-provided copy
        cp /usr/share/dns/root.hints "$ROOT_HINTS" 2>/dev/null || \
        cp /usr/share/unbound/root.hints "$ROOT_HINTS" 2>/dev/null || \
        echo "[entrypoint] WARNING: no root.hints found — resolution may fail"
        chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || true
    fi
fi

# Copy DNSSEC trust anchor from package if not present
ROOT_KEY="/var/lib/unbound/root.key"
if [ ! -f "$ROOT_KEY" ]; then
    echo "[entrypoint] Initializing DNSSEC trust anchor..."
    # unbound-anchor manages the root trust anchor
    unbound-anchor -a "$ROOT_KEY" || true
    chown unbound:unbound "$ROOT_KEY" 2>/dev/null || true
fi

# Validate config before starting
echo "[entrypoint] Validating configuration..."
unbound-checkconf /etc/unbound/unbound.conf

echo "[entrypoint] Starting Unbound $(unbound -V 2>&1 | head -1)..."
exec unbound -d -c /etc/unbound/unbound.conf
