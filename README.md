# unbound-container

A minimal, privacy-focused [Unbound](https://nlnetlabs.nl/projects/unbound/) recursive DNS resolver container.  
Designed to run as a Pi-hole upstream resolver — no third-party DNS provider, full DNSSEC validation.

**Supported architectures:** `linux/amd64` · `linux/arm64` · `linux/riscv64`  
**Base image:** Debian Trixie slim  
**Unbound version:** see `UPSTREAM_VERSION`

---

## What is Unbound?

Unbound is a validating, recursive, caching DNS resolver. Unlike forwarding resolvers which send your queries to Cloudflare or Google, Unbound resolves queries **directly against the root DNS servers** — no third party ever sees your queries.

Combined with Pi-hole:

```
Your devices → Pi-hole (blocks ads/trackers) → Unbound (recursive) → Root servers
                                                      ↓
                                             DNSSEC validated
                                             Query minimization
                                             No third party
```

---

## Quick Start

### 1. Copy sample files

```bash
cp unbound.conf.sample unbound.conf
cp docker-compose.sample.yml docker-compose.yml
cp .env.sample .env
```

### 2. Edit your config

```bash
# Set your timezone, paths, passwords
nano .env

# Customize DNS settings (local TLD, broken DNSSEC domains, etc.)
nano unbound.conf
```

### 3. Create the data directory

```bash
mkdir -p /srv/docker/cont/unbound/data
```

### 4. Start

```bash
docker compose up -d
```

---

## Configuration

### Environment Variables

All tunable without rebuilding the image:

| Variable | Default | Description |
|----------|---------|-------------|
| `UNBOUND_PORT` | `5053` | Port Unbound listens on |
| `UNBOUND_THREADS` | `2` | CPU threads |
| `UNBOUND_MSG_CACHE` | `32m` | Message cache size |
| `UNBOUND_RRSET_CACHE` | `64m` | RRSET cache size (keep at 2x msg) |

### Custom Config File

Mount your own `unbound.conf` to override the built-in defaults:

```yaml
volumes:
  - /path/to/unbound.conf:/etc/unbound/unbound.conf:ro
```

Start from the provided `unbound.conf.sample` and customize as needed.

### Performance Tuning

Adjust cache sizes based on available RAM:

| RAM | `UNBOUND_THREADS` | `UNBOUND_MSG_CACHE` | `UNBOUND_RRSET_CACHE` |
|-----|-------------------|---------------------|----------------------|
| 1 GB | 1 | 16m | 32m |
| 2 GB | 2 | 32m | 64m |
| 4 GB | 2 | 32m | 64m |
| 8 GB+ | 4 | 64m | 128m |

### Local TLD

Add your custom local domain TLD to `unbound.conf`:

```
private-domain: "yourtld"
domain-insecure: "yourtld"
```

This prevents Unbound from trying to validate or forward your local domains to root servers.

---

## Integration with Pi-hole

### Network Setup

The recommended approach is `network_mode: service:pihole` — Unbound shares Pi-hole's network stack and is reachable via `127.0.0.1`. This avoids hostname resolution issues in dnsmasq.

```yaml
services:
  unbound:
    image: ghcr.io/mmbesar/unbound-container:latest
    network_mode: "service:pihole"
    depends_on:
      pihole:
        condition: service_started
    environment:
      UNBOUND_PORT: "5053"
    volumes:
      - /srv/docker/cont/unbound/data:/var/lib/unbound
      - /srv/docker/cont/unbound/unbound.conf:/etc/unbound/unbound.conf:ro

  pihole:
    image: pihole/pihole:latest
    environment:
      FTLCONF_dns_upstreams: "127.0.0.1#5053"
```

### Startup Timing

~15 seconds of DNS errors at Pi-hole startup while Unbound primes DNSSEC is **normal and expected**. Pi-hole starts first (to create the network namespace), Unbound joins, primes its trust anchor, then Pi-hole routes DNS cleanly. No intervention needed.

---

## Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/unbound` | Persistent data — `root.key` and `root.hints` |
| `/etc/unbound/unbound.conf` | Config — mount your own to override defaults |

Always mount `/var/lib/unbound` to a named volume or host path. Without persistence, the DNSSEC trust anchor is regenerated on every restart (slow, network-dependent).

---

## Troubleshooting

### Domains returning SERVFAIL

SERVFAIL means Unbound rejected the DNS response — usually for one of two reasons:

**1. DNSSEC validation failure (broken DNSSEC on the domain's side)**

Some domains, particularly banking sites and country-specific TLDs, have misconfigured or missing DNSSEC. Unbound correctly rejects these but this breaks access.

Diagnose:
```bash
docker exec pihole dig @unbound -p 5053 problem-domain.com +dnssec
```

If result is `SERVFAIL` — add to `unbound.conf`:
```
domain-insecure: "problem-domain.com"
# Or for an entire country TLD:
domain-insecure: "com.eg"
```

Restart the container — no rebuild needed.

**2. `use-caps-for-id` incompatibility**

Some nameservers don't support 0x20 random case encoding and return mangled responses. If a specific domain consistently fails, try setting:
```
use-caps-for-id: no
```

This is already set to `no` in the sample config.

### Checking if DNSSEC validation works

Test with an intentionally broken DNSSEC domain:
```bash
docker exec pihole dig @unbound -p 5053 dnssec-failed.org +dnssec
```

Should return `SERVFAIL` — this confirms validation is working correctly.

Test with a properly signed domain:
```bash
docker exec pihole dig @unbound -p 5053 cloudflare.com +dnssec
```

Should return `NOERROR` with `ad` flag — authenticated data, DNSSEC valid.

### Root hints update fails at startup

Unbound tries to fetch fresh root hints from IANA at startup. If your network isn't ready yet, it falls back to the packaged copy. This is harmless — the root server list changes very rarely.

### Checking logs

```bash
docker logs unbound
docker logs unbound 2>&1 | grep -iE "error|warn|fail"
```

Clean startup looks like:
```
[entrypoint] root.hints updated from IANA
[entrypoint] success: the anchor is ok
[entrypoint] Validating configuration...
unbound-checkconf: no errors in /tmp/unbound.conf
[entrypoint] Starting Unbound 1.22.0 on port 5053...
[unbound] info: start of service (unbound 1.22.0).
```

### Verify end-to-end DNS

```bash
# Through Pi-hole
nslookup google.com your-pihole-ip

# Directly to Unbound (from within Pi-hole container)
docker exec pihole dig @unbound -p 5053 cloudflare.com A

# DNS leak test
# Visit https://dnsleaktest.com — should show only your ISP
```

---

## Rebuild Schedule

The image rebuilds automatically every Sunday at 02:00 UTC via GitHub Actions, picking up the latest Unbound package from Debian Trixie.

---

## Security Notes

- Unbound runs as the `unbound` system user (drops privileges after binding)
- Only accepts queries from private network ranges — never exposed to internet
- DNSSEC validation enabled by default
- Query name minimization reduces data leakage to root/TLD servers
- DNS rebinding protection blocks private IPs in public DNS responses

---

## License

MIT — see [LICENSE](LICENSE)

Unbound is developed by [NLnet Labs](https://nlnetlabs.nl/) under BSD license.
