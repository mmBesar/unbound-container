# unbound-container
# Minimal Unbound recursive DNS resolver
# Built from official Debian Trixie packages — no compilation needed
# Supports: linux/amd64, linux/arm64, linux/riscv64
#
# github.com/mmBesar/unbound-container

FROM debian:trixie-slim

ARG VERSION="unknown"
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"

LABEL org.opencontainers.image.title="unbound-container" \
      org.opencontainers.image.description="Unbound recursive DNS resolver — amd64/arm64/riscv64" \
      org.opencontainers.image.url="https://github.com/mmBesar/unbound-container" \
      org.opencontainers.image.source="https://github.com/mmBesar/unbound-container" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="mmBesar"

# Install unbound and dns-root-data
# curl is needed to refresh root.hints at runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unbound \
        dns-root-data \
        curl \
        ca-certificates \
        dnsutils && \
    # Remove default config — we supply our own
    rm -f /etc/unbound/unbound.conf && \
    # Create runtime directory and set permissions
    # unbound package creates the unbound user — verify it exists
    id unbound && \
    mkdir -p /var/lib/unbound && \
    chown -R unbound:unbound /etc/unbound /var/lib/unbound && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy our optimized config
COPY unbound.conf /etc/unbound/unbound.conf

# Copy entrypoint — runs as root to refresh root.hints then drops to unbound user
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    chown unbound:unbound /etc/unbound/unbound.conf

# DNS port — Pi-hole connects here
EXPOSE 5053/udp
EXPOSE 5053/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD nslookup -port=5053 cloudflare.com 127.0.0.1 > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
