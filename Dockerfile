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
    id unbound && \
    mkdir -p /var/lib/unbound /etc/unbound && \
    chown unbound:unbound /var/lib/unbound /etc/unbound && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Default config — good general defaults, works out of the box
# Override by mounting your own: -v /path/to/unbound.conf:/etc/unbound/unbound.conf:ro
COPY unbound.conf /etc/unbound/unbound.conf.default

# Entrypoint handles root.hints, root.key, and config setup
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables — tune without rebuilding the image
# Override any of these in your compose file or docker run command
ENV UNBOUND_PORT=5053 \
    UNBOUND_THREADS=2 \
    UNBOUND_MSG_CACHE=32m \
    UNBOUND_RRSET_CACHE=64m

# /var/lib/unbound — persistent data (root.key, root.hints)
# /etc/unbound    — config (mount your own unbound.conf here to override)
VOLUME ["/var/lib/unbound"]

EXPOSE 5053/udp
EXPOSE 5053/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=10 \
    CMD nslookup -port=5053 cloudflare.com 127.0.0.1 > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
