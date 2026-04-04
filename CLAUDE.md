## Project

**MTProto Proxy for Telegram**

A self-hosted MTProto proxy (using the `mtg` Go implementation) deployed via Docker Compose on a VPS, enabling users to access Telegram in restricted networks. Traffic is disguised as HTTPS via fake-TLS to avoid deep packet inspection.

**Core Value:** Users can reliably access Telegram at all times — the proxy must stay up, stay hidden, and be easy to connect to.

### Constraints

- **Traffic disguise**: Must use fake-TLS — plain MTProto connections are trivially detected and blocked
- **Provider**: Must be hosted on a VPS with IP ranges reachable from the target region
- **Simplicity**: End users are non-technical — connection must be a single `tg://proxy?` link
- **Reliability**: Must survive reboots and crashes without manual intervention

## Technology Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Proxy | [mtg v2](https://github.com/9seconds/mtg) (`nineseconds/mtg:2`) | Go MTProto proxy with native fake-TLS support |
| Orchestration | Docker Compose v2 | `docker compose` (not deprecated v1 `docker-compose`) |
| Auto-update | Watchtower (`containrrr/watchtower`) | Label-scoped to mtg only, daily 2 AM cron |
| Monitoring | Uptime Kuma (external) | TCP check on port 443 |
| Config | `.env` file | Port, domain, secret — no YAML editing needed |
| Setup | `setup.sh` | Idempotent: installs Docker, generates secret, deploys stack, prints `tg://proxy?` link |

### What NOT to Use

- **Official C MTProxy** — no fake-TLS, harder to Dockerize, stale maintenance
- **mtg v1** — deprecated, incompatible `dd`-prefix secret format (no TLS disguise)
- **Reverse proxy in front of mtg** (nginx/Traefik) — breaks fake-TLS fingerprint
- **Kubernetes/Nomad** — massive overkill for a single VPS

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Fake-TLS with `microsoft.com` default | High-traffic domain, unlikely to be blocked; configurable via `FAKETLS_DOMAIN` env var |
| Port 443 default | Makes traffic look like HTTPS to DPI |
| `restart: unless-stopped` | Survives crashes and VPS reboots |
| Watchtower label-enable scoping | Only updates mtg, not all containers on the host |
| Stats port bound to `127.0.0.1` only | Prevents fingerprinting the proxy via exposed health endpoint |
| TCP health check on 443 (not HTTP stats) | Simpler, catches same failure modes, no firewall config needed |
| Smoke tests run offline | No Docker required to validate the deployment kit |

## Deployment Pitfalls

Critical operational knowledge — these determine whether the proxy works at all.

### VPS IP Range Already Blocked
Some hosting providers have IP ranges blocked by ISPs in restricted regions. Test reachability from the target region **before** committing to a provider. Symptoms: connections time out (not refused) at the ISP boundary.

### Fake-TLS Domain Triggers DPI Mismatch
Sophisticated DPI can check whether the SNI hostname matches the destination IP's ASN. `microsoft.com` traffic going to a small hosting provider's IP is anomalous. Best option: own the fake-TLS domain and point its A record at the VPS IP.

### Secret Format Errors
Proxy secrets must start with `ee` hex prefix (fake-TLS encoding). Always use `mtg generate-secret --hex <domain>` — never construct manually. Wrong format means either broken links or connections without TLS disguise.

### Port 443 Blocked at Firewall
Docker's iptables rules bypass UFW, but provider-level cloud firewalls sit outside the VPS. Check all firewall layers. Test from outside: `nc -zv <VPS-IP> 443`.

### Auto-Update Breaks Container
Major mtg version bumps can break config format. Watchtower on `latest` without oversight risks silent crash loops. Pin to major version tag (`nineseconds/mtg:2`), monitor with Uptime Kuma.

### Health Endpoint Exposed Publicly
The mtg stats port (default 3129) is a fingerprint. Never expose it to the internet — bind to `127.0.0.1` only in Docker Compose port mappings.

## Project Structure

```
├── docker-compose.yml    # mtg + Watchtower services
├── setup.sh              # Idempotent VPS bootstrap script
├── tests/smoke.sh        # 38 offline assertions validating the deployment kit
└── CLAUDE.md             # This file
```

Runtime files created by `setup.sh` on the VPS:
- `/opt/mtproto-proxy/.env` — secrets and config (MTG_SECRET, MTG_PORT, MTG_DOMAIN, VPS_IP)
- `/opt/mtproto-proxy/config.toml` — generated mtg TOML config

## Testing

Run `bash tests/smoke.sh` — validates docker-compose.yml, setup.sh, and config generation logic offline (no Docker daemon required). Uses `assert`/`assert_not` helper pattern.

## Future Considerations (Not in Scope)

- Secret rotation script
- Warm-standby on a second provider for failover
- Firewall hardening (ufw rules for ports 22 + 443 only)
- Docker image pinned to specific digest (not just tag)
- Encrypted DNS (DoH/DoT) to prevent DNS-based proxy identification
