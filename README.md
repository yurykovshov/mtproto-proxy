# MTProto Proxy

A self-hosted [MTProto proxy](https://core.telegram.org/mtproto) for Telegram, deployed via Docker Compose on a VPS. Traffic is disguised as HTTPS using fake-TLS to avoid deep packet inspection.

## Features

- **Fake-TLS obfuscation** — traffic looks like HTTPS to DPI systems
- **One-command setup** — idempotent script installs Docker, generates secrets, deploys the stack
- **Auto-updates** — Watchtower keeps the proxy image current
- **Auto-restart** — survives crashes and VPS reboots
- **Zero maintenance** — share a `tg://proxy?` link with users, done

## Quick Start

```bash
# SSH into a fresh VPS (Ubuntu/Debian), then:
curl -fsSL https://raw.githubusercontent.com/yurykovshov/mtproto-proxy/main/setup.sh -o setup.sh
curl -fsSL https://raw.githubusercontent.com/yurykovshov/mtproto-proxy/main/docker-compose.yml -o docker-compose.yml
chmod +x setup.sh
sudo ./setup.sh
```

The script will:
1. Install Docker (if not present)
2. Generate a fake-TLS proxy secret
3. Deploy the proxy and Watchtower containers
4. Print a `tg://proxy?` connection link

Share the link with your users — they tap it in Telegram and the proxy is configured automatically.

## Configuration

All settings are in `.env` (created by `setup.sh` at `/opt/mtproto-proxy/.env`):

| Variable | Default | Description |
|----------|---------|-------------|
| `MTG_PORT` | `443` | Proxy listen port (443 recommended for HTTPS disguise) |
| `MTG_DOMAIN` | `microsoft.com` | Fake-TLS camouflage domain |
| `MTG_SECRET` | *(generated)* | Proxy secret (ee-prefix, fake-TLS encoded) |
| `VPS_IP` | *(auto-detected)* | Server public IP address |

To change the fake-TLS domain before first run:

```bash
MTG_DOMAIN=apple.com sudo ./setup.sh
```

## Re-running the Setup Script

The script is idempotent. If a deployment already exists, it offers:

1. **Show connection link** — print the `tg://proxy?` link again
2. **Update and restart** — pull latest image and restart the proxy
3. **Abort**

Existing secrets are never overwritten.

## How It Works

```
User's Telegram app
    │
    │  tg://proxy? link
    ▼
┌──────────────┐
│   mtg proxy  │  ← fake-TLS on port 443 (looks like HTTPS)
│  (Docker)    │
└──────┬───────┘
       │
       ▼
  Telegram servers
```

- **mtg** handles fake-TLS termination — no reverse proxy needed in front of it
- **Watchtower** checks for new mtg images daily at 2 AM and restarts automatically
- Health monitoring via external [Uptime Kuma](https://github.com/louislam/uptime-kuma) TCP check on port 443

## Requirements

- A VPS running Ubuntu/Debian (1 CPU, 512 MB RAM is sufficient)
- VPS IP reachable from the target region (test before committing to a provider)
- Port 443 open in all firewall layers (VPS + provider-level)

## Testing

Offline smoke tests validate the deployment kit without requiring Docker:

```bash
bash tests/smoke.sh
```

## License

MIT
