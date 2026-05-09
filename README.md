# unbound-container

A minimal, privacy-focused [Unbound](https://nlnetlabs.nl/projects/unbound/) recursive DNS resolver container.

Built from official Debian Trixie packages. No compilation. Designed to run as a Pi-hole upstream resolver.

**Supported architectures:** `linux/amd64` · `linux/arm64` · `linux/riscv64`

---

## What is Unbound?

Unbound is a validating, recursive, caching DNS resolver. Unlike forwarding resolvers (which send your queries to Cloudflare, Google, etc.), Unbound resolves queries **directly against the root DNS servers** — no third party ever sees your queries.

Combined with Pi-hole for ad blocking, this gives you:

```
Devices → Pi-hole (blocks ads) → Unbound (recursive) → Root servers
```

- No third-party DNS provider
- Full DNSSEC validation
- Query name minimization (hides full domain from root servers)
- DNS rebinding protection

---

## Usage

### Docker Compose (with Pi-hole)

```yaml
services:
  unbound:
    image: ghcr.io/mmbesar/unbound-container:latest
    container_name: unbound
    networks:
      - net
    restart: always

  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    environment:
      FTLCONF_dns_upstreams: "unbound#5053"
    # ... rest of your Pi-hole config
```

### Standalone

```bash
docker run -d \
  --name unbound \
  -p 5053:5053/udp \
  -p 5053:5053/tcp \
  ghcr.io/mmbesar/unbound-container:latest
```

---

## Configuration

### Default config

The default `unbound.conf` is tuned for:
- Low RAM usage (suitable for 4GB single-board computers)
- Full DNSSEC validation
- Query name minimization
- DNS rebinding protection
- Local domain handling (`local`, `lan`, `home`, `mm`)

### Custom config

Mount your own config to override the default:

```yaml
volumes:
  - /path/to/your/unbound.conf:/etc/unbound/unbound.conf:ro
```

### Tuning for your hardware

Edit `num-threads`, `msg-cache-size`, and `rrset-cache-size` in `unbound.conf`:

| Board RAM | num-threads | msg-cache-size | rrset-cache-size |
|-----------|-------------|----------------|------------------|
| 1 GB      | 1           | 16m            | 32m              |
| 2 GB      | 2           | 32m            | 64m              |
| 4 GB      | 2           | 32m            | 64m              |
| 8 GB+     | 4           | 64m            | 128m             |

### Local TLD

If your local domain TLD is not `local`, `lan`, `home`, or `mm`, add it to `unbound.conf`:

```
private-domain: "yourtld"
domain-insecure: "yourtld"
```

---

## Root hints

Root hints are automatically refreshed from `https://www.internic.net/domain/named.root` on each container start. If the fetch fails, the existing copy is used. The `dns-root-data` Debian package provides a fallback.

---

## Verify it's working

```bash
# Test basic resolution
docker exec unbound nslookup -port=5053 cloudflare.com 127.0.0.1

# Test DNSSEC validation (should return SERVFAIL — intentionally broken)
docker exec unbound nslookup -port=5053 dnssec-failed.org 127.0.0.1

# Check logs
docker logs unbound
```

---

## Pi-hole integration

In your Pi-hole compose environment:

```yaml
FTLCONF_dns_upstreams: "unbound#5053"
```

Both containers must be on the same Docker network so Pi-hole can reach Unbound by container name.

---

## Rebuild schedule

The image rebuilds automatically every Sunday at 02:00 UTC via GitHub Actions, picking up the latest Unbound package from Debian Trixie.

---

## License

MIT — see [LICENSE](LICENSE)

Unbound is developed by [NLnet Labs](https://nlnetlabs.nl/) and licensed under BSD.
