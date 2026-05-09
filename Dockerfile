# unbound-container
# Minimal Unbound recursive DNS resolver
# Built from official Debian Trixie packages
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

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unbound \
        unbound-anchor \
        dns-root-data \
        curl \
        ca-certificates \
        dnsutils && \
    # Verify unbound user exists
    id unbound && \
    # Create data directory — will be overridden by volume mount
    mkdir -p /var/lib/unbound && \
    chown unbound:unbound /var/lib/unbound && \
    # Remove default config — we supply our own
    rm -f /etc/unbound/unbound.conf && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy config and entrypoint
COPY unbound.conf /etc/unbound/unbound.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    chown unbound:unbound /etc/unbound/unbound.conf

# Environment variables — all configurable, nothing hardcoded
# UNBOUND_PORT: port Unbound listens on (default 5053)
# UNBOUND_THREADS: number of threads (default 2)
# UNBOUND_MSG_CACHE: message cache size (default 32m)
# UNBOUND_RRSET_CACHE: rrset cache size (default 64m)
ENV UNBOUND_PORT=5053 \
    UNBOUND_THREADS=2 \
    UNBOUND_MSG_CACHE=32m \
    UNBOUND_RRSET_CACHE=64m

# Data volume — root.key and root.hints persist here
VOLUME ["/var/lib/unbound"]

EXPOSE 5053/udp
EXPOSE 5053/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD nslookup -port=5053 cloudflare.com 127.0.0.1 > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
