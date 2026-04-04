#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/mtproto-proxy"
ENV_FILE="$WORKDIR/.env"
COMPOSE_FILE="$WORKDIR/docker-compose.yml"
CONFIG_FILE="$WORKDIR/config.toml"
LINK_FILE="$HOME/proxy-link.txt"
DEFAULT_PORT=443
DEFAULT_DOMAIN="microsoft.com"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

log_step() { echo "==> $1"; }
log_ok()   { echo "  [OK] $1"; }
log_fail() { echo "  [FAIL] $1" >&2; }

show_link() {
    source "$ENV_FILE"
    local link="tg://proxy?server=${VPS_IP}&port=${MTG_PORT}&secret=${MTG_SECRET}"
    echo ""
    echo "Connection link:"
    echo "$link"
    echo "$link" > "$LINK_FILE"
    echo ""
    echo "Link saved to: $LINK_FILE"
}

generate_config() {
    source "$ENV_FILE"
    cat > "$CONFIG_FILE" <<TOML
secret = "${MTG_SECRET}"
bind-to = "0.0.0.0:${MTG_PORT}"
TOML
}

install_docker() {
    if command -v docker &>/dev/null; then
        log_ok "Docker already installed: $(docker --version 2>/dev/null || true)"
    else
        log_step "Installing Docker..."
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER"
        log_ok "Docker installed"
    fi
}

detect_ip() {
    local ip
    ip=$(curl -4 -s --connect-timeout 5 https://api.ipify.org \
         || curl -4 -s --connect-timeout 5 https://ifconfig.me \
         || curl -4 -s --connect-timeout 5 https://icanhazip.com \
         || echo "")
    if [[ -z "$ip" ]]; then
        read -rp "Could not detect VPS IP. Enter IP address: " ip
    else
        read -rp "Detected IP: ${ip}. Press Enter to confirm or type correct IP: " override
        ip="${override:-$ip}"
    fi
    echo "$ip"
}

generate_secret() {
    local domain="$1"
    local secret
    secret=$(sudo docker run --rm nineseconds/mtg:2 generate-secret --hex "$domain")
    if [[ "${secret:0:2}" != "ee" ]]; then
        log_fail "Generated secret does not start with 'ee' prefix — expected fake-TLS secret. Got: $secret"
        exit 1
    fi
    echo "$secret"
}

# ---------------------------------------------------------------------------
# link subcommand
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "link" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        log_fail "No deployment found. Run setup.sh first."
        exit 1
    fi
    show_link
    exit 0
fi

# ---------------------------------------------------------------------------
# Re-run detection
# ---------------------------------------------------------------------------

if [[ -f "$ENV_FILE" ]] && grep -q "^MTG_SECRET=ee" "$ENV_FILE"; then
    echo ""
    echo "Existing deployment detected at $WORKDIR"
    echo ""
    echo "  [1] Show connection link"
    echo "  [2] Update and restart proxy"
    echo "  [3] Abort"
    echo ""
    read -rp "Choose [1/2/3]: " choice
    case "$choice" in
        1) show_link; exit 0 ;;
        2)
            log_step "Updating deployment..."
            generate_config
            cd "$WORKDIR"
            sudo docker compose pull
            sudo docker compose up -d
            log_ok "Proxy restarted"
            show_link
            exit 0
            ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------------------
# Fresh install flow
# ---------------------------------------------------------------------------

log_step "Installing Docker..."
install_docker

log_step "Creating working directory..."
sudo mkdir -p "$WORKDIR"
sudo chown "$USER:$USER" "$WORKDIR"
log_ok "Working directory ready: $WORKDIR"

log_step "Detecting VPS IP..."
VPS_IP=$(detect_ip)
log_ok "VPS IP: $VPS_IP"

MTG_DOMAIN="${MTG_DOMAIN:-$DEFAULT_DOMAIN}"

log_step "Generating proxy secret (domain: $MTG_DOMAIN)..."
MTG_SECRET=$(generate_secret "$MTG_DOMAIN")
log_ok "Secret generated (ee-prefix confirmed)"

log_step "Writing configuration..."
cat > "$ENV_FILE" <<ENV
MTG_SECRET=${MTG_SECRET}
MTG_PORT=${MTG_PORT:-$DEFAULT_PORT}
MTG_DOMAIN=${MTG_DOMAIN}
VPS_IP=${VPS_IP}
ENV

generate_config
cp "$(dirname "$0")/docker-compose.yml" "$COMPOSE_FILE"
log_ok "Config files written to $WORKDIR"

log_step "Starting proxy..."
cd "$WORKDIR"
sudo docker compose up -d
log_ok "Proxy started"

log_step "Verifying proxy..."
sleep 3
if sudo docker compose ps --format json 2>/dev/null | grep -q '"State":"running"' || \
   sudo docker compose ps 2>/dev/null | grep -q "Up"; then
    log_ok "Proxy container is running"
else
    log_fail "Proxy container may not be running — check: sudo docker compose -f $COMPOSE_FILE ps"
fi

show_link

echo ""
echo "Setup complete!"
echo ""
echo "To retrieve the link later: $0 link"
echo "Proxy files: $WORKDIR"
echo "Link saved to: $LINK_FILE"
