#!/bin/bash
# unbound-container entrypoint
# Handles: config setup, root.hints refresh, DNSSEC trust anchor, env overrides
set -euo pipefail

DATA_DIR="/var/lib/unbound"
CONFIG="/etc/unbound/unbound.conf"
CONFIG_DEFAULT="/etc/unbound/unbound.conf.default"
ROOT_HINTS="${DATA_DIR}/root.hints"
ROOT_KEY="${DATA_DIR}/root.key"
ROOT_HINTS_URL="https://www.internic.net/domain/named.root"

# ── Config setup ─────────────────────────────────────────────────────────────
# If user has not mounted their own unbound.conf, use the default
if [ ! -f "$CONFIG" ]; then
    echo "[entrypoint] No custom config found — using default"
    cp "$CONFIG_DEFAULT" "$CONFIG"
    chown unbound:unbound "$CONFIG" 2>/dev/null || true
else
    echo "[entrypoint] Using custom config: $CONFIG"
fi

# ── Apply environment variable overrides ─────────────────────────────────────
echo "[entrypoint] Applying environment overrides..."
echo "  UNBOUND_PORT=${UNBOUND_PORT}"
echo "  UNBOUND_THREADS=${UNBOUND_THREADS}"
echo "  UNBOUND_MSG_CACHE=${UNBOUND_MSG_CACHE}"
echo "  UNBOUND_RRSET_CACHE=${UNBOUND_RRSET_CACHE}"

# Copy config to writable temp location before sed
# Handles read-only mounts (:ro) cleanly
WORKING_CONFIG="/tmp/unbound.conf"
cp "$CONFIG" "$WORKING_CONFIG"
CONFIG="$WORKING_CONFIG"

sed -i "s|interface: 0.0.0.0@5053|interface: 0.0.0.0@${UNBOUND_PORT}|g" "$CONFIG"
sed -i "s|interface: ::0@5053|interface: ::0@${UNBOUND_PORT}|g" "$CONFIG"
sed -i "s|num-threads: 2|num-threads: ${UNBOUND_THREADS}|g" "$CONFIG"
sed -i "s|msg-cache-size: 32m|msg-cache-size: ${UNBOUND_MSG_CACHE}|g" "$CONFIG"
sed -i "s|rrset-cache-size: 64m|rrset-cache-size: ${UNBOUND_RRSET_CACHE}|g" "$CONFIG"

# ── Data directory ownership ──────────────────────────────────────────────────
chown -R unbound:unbound "$DATA_DIR" 2>/dev/null || true

# ── Root hints ────────────────────────────────────────────────────────────────
echo "[entrypoint] Refreshing root.hints..."
if curl -fsSL --max-time 15 "$ROOT_HINTS_URL" -o "${ROOT_HINTS}.tmp" 2>/dev/null; then
    mv "${ROOT_HINTS}.tmp" "$ROOT_HINTS"
    chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || true
    echo "[entrypoint] root.hints updated from IANA"
else
    echo "[entrypoint] Could not fetch root.hints — using existing or package fallback"
    if [ ! -f "$ROOT_HINTS" ]; then
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

# ── DNSSEC trust anchor ───────────────────────────────────────────────────────
if [ ! -f "$ROOT_KEY" ]; then
    echo "[entrypoint] Initializing DNSSEC trust anchor (first run)..."
    unbound-anchor -a "$ROOT_KEY" -v || true
    chown unbound:unbound "$ROOT_KEY" 2>/dev/null || true
else
    echo "[entrypoint] Updating DNSSEC trust anchor..."
    unbound-anchor -a "$ROOT_KEY" -v || true
fi

if [ ! -f "$ROOT_KEY" ]; then
    echo "[entrypoint] ERROR: Could not create root.key"
    echo "[entrypoint] Check network connectivity and try again"
    exit 1
fi

# ── Validate config ───────────────────────────────────────────────────────────
echo "[entrypoint] Validating configuration..."
unbound-checkconf "$CONFIG"

# ── Start ─────────────────────────────────────────────────────────────────────
echo "[entrypoint] Starting Unbound $(unbound -V 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+') on port ${UNBOUND_PORT}..."
exec unbound -d -c "$CONFIG"
