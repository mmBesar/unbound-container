#!/bin/bash
# unbound-container entrypoint
# All paths use /var/lib/unbound — mount a volume there for persistence
set -euo pipefail

DATA_DIR="/var/lib/unbound"
ROOT_HINTS="${DATA_DIR}/root.hints"
ROOT_KEY="${DATA_DIR}/root.key"
ROOT_HINTS_URL="https://www.internic.net/domain/named.root"
CONFIG="/etc/unbound/unbound.conf"

# ── Generate config from environment variables ────────────────────────────────
# This allows tuning without rebuilding the image
echo "[entrypoint] Configuring Unbound..."
echo "  UNBOUND_PORT=${UNBOUND_PORT}"
echo "  UNBOUND_THREADS=${UNBOUND_THREADS}"
echo "  UNBOUND_MSG_CACHE=${UNBOUND_MSG_CACHE}"
echo "  UNBOUND_RRSET_CACHE=${UNBOUND_RRSET_CACHE}"

# Apply env overrides by replacing values in config
sed -i "s|interface: 0.0.0.0@5053|interface: 0.0.0.0@${UNBOUND_PORT}|g" "$CONFIG"
sed -i "s|interface: ::0@5053|interface: ::0@${UNBOUND_PORT}|g" "$CONFIG"
sed -i "s|num-threads: 2|num-threads: ${UNBOUND_THREADS}|g" "$CONFIG"
sed -i "s|msg-cache-size: 32m|msg-cache-size: ${UNBOUND_MSG_CACHE}|g" "$CONFIG"
sed -i "s|rrset-cache-size: 64m|rrset-cache-size: ${UNBOUND_RRSET_CACHE}|g" "$CONFIG"

# ── Ensure data directory is writable ────────────────────────────────────────
# When running as root (default), fix ownership of mounted volume
if [ "$(id -u)" = "0" ]; then
    chown -R unbound:unbound "$DATA_DIR" 2>/dev/null || true
fi

# ── Refresh root.hints ────────────────────────────────────────────────────────
echo "[entrypoint] Refreshing root.hints..."
if curl -fsSL --max-time 15 "$ROOT_HINTS_URL" -o "${ROOT_HINTS}.tmp" 2>/dev/null; then
    mv "${ROOT_HINTS}.tmp" "$ROOT_HINTS"
    chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || true
    echo "[entrypoint] root.hints updated"
else
    echo "[entrypoint] Could not fetch root.hints — using existing or package copy"
    if [ ! -f "$ROOT_HINTS" ]; then
        # Fall back to package-provided copy
        for fallback in /usr/share/dns/root.hints /usr/share/unbound/root.hints; do
            if [ -f "$fallback" ]; then
                cp "$fallback" "$ROOT_HINTS"
                chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || true
                echo "[entrypoint] Using fallback: $fallback"
                break
            fi
        done
    fi
fi

# ── Initialize DNSSEC trust anchor ────────────────────────────────────────────
if [ ! -f "$ROOT_KEY" ]; then
    echo "[entrypoint] Initializing DNSSEC trust anchor (first run)..."
    # unbound-anchor fetches and validates the root trust anchor
    unbound-anchor -a "$ROOT_KEY" -v || true
    chown unbound:unbound "$ROOT_KEY" 2>/dev/null || true
else
    echo "[entrypoint] Updating DNSSEC trust anchor..."
    unbound-anchor -a "$ROOT_KEY" -v || true
fi

if [ ! -f "$ROOT_KEY" ]; then
    echo "[entrypoint] ERROR: Could not create root.key — DNSSEC will not work"
    echo "[entrypoint] Check network connectivity and try again"
    exit 1
fi

# ── Validate config ───────────────────────────────────────────────────────────
echo "[entrypoint] Validating configuration..."
unbound-checkconf "$CONFIG"

# ── Start Unbound ─────────────────────────────────────────────────────────────
echo "[entrypoint] Starting Unbound on port ${UNBOUND_PORT}..."
exec unbound -d -c "$CONFIG"
