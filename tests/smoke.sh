#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"

assert() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_not() {
    local desc="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== docker-compose.yml ==="
DC="$SCRIPT_DIR/docker-compose.yml"
assert "File exists" test -f "$DC"
assert "Uses nineseconds/mtg:2 image (PROXY-01, D-10, D-11)" grep -q "image: nineseconds/mtg:2" "$DC"
assert "Has restart: unless-stopped (DEPLOY-01)" grep -q "restart: unless-stopped" "$DC"
assert "Port mapping uses MTG_PORT env var (PROXY-02, DEPLOY-02)" grep -q '${MTG_PORT}' "$DC"
assert "Mounts config.toml read-only" grep -q "config.toml:/config.toml:ro" "$DC"
assert "Uses run subcommand" grep -q "run /config.toml" "$DC"
assert_not "No version: key (Compose v2)" grep -q "^version:" "$DC"
assert_not "No container_name directive" grep -q "container_name:" "$DC"

echo ""
echo "=== setup.sh ==="
SS="$SCRIPT_DIR/setup.sh"
assert "File exists" test -f "$SS"
assert "Is executable" test -x "$SS"
assert "Valid bash syntax" bash -n "$SS"
assert "Has bash shebang" head -1 "$SS" | grep -q "bash"
assert "Has strict mode (set -euo pipefail)" grep -q "set -euo pipefail" "$SS"
assert "Generates secret via mtg generate-secret --hex (PROXY-03)" grep -q "generate-secret --hex" "$SS"
assert "Constructs tg://proxy link (PROXY-04)" grep -q "tg://proxy?server=" "$SS"
assert "Default domain is microsoft.com (PROXY-05)" grep -q 'microsoft.com' "$SS"
assert "Checks for ee-prefix secret on re-run (DEPLOY-05)" grep -q 'MTG_SECRET=ee' "$SS"
assert "Has link subcommand (D-07)" grep -q '"link"' "$SS"
assert "Saves link to proxy-link.txt (D-08)" grep -q "proxy-link.txt" "$SS"
assert "Uses sudo docker (Pitfall 5)" grep -q "sudo docker" "$SS"
assert "Installs Docker via get.docker.com (D-02)" grep -q "get.docker.com" "$SS"
assert "Has interactive re-run menu (D-05)" grep -q "Existing deployment detected" "$SS"
assert "Copies docker-compose.yml to workdir" grep -q "docker-compose.yml" "$SS"
assert "Generates config.toml with bind-to (Pitfall 3)" grep -q 'bind-to' "$SS"
assert "Uses docker compose (v2, not docker-compose)" grep -q "docker compose" "$SS"
assert_not "Does not use docker-compose v1 command" grep -q "docker-compose " "$SS"
assert "Configures firewall (ufw allow 22 and 443)" grep -q "ufw allow 22/tcp" "$SS"
assert "Opens port 443 in firewall" grep -q "ufw allow 443/tcp" "$SS"
assert "Detects VPS IP with fallback (Pitfall 2)" grep -q "ifconfig.me\|ipify\|icanhazip" "$SS"
assert "Secret stored in .env not Docker volume (DEPLOY-03)" grep -q 'MTG_SECRET=' "$SS"

echo ""
echo "=== Phase 2: Auto-Update and Monitoring ==="
assert "Watchtower service present (REL-01)" grep -q "containrrr/watchtower" "$DC"
assert "Watchtower has restart: unless-stopped (REL-03, D-06)" bash -c "grep -A5 'watchtower:' '$DC' | grep -q 'unless-stopped'"
assert "mtg has watchtower enable label (REL-01, D-02)" grep -q "com.centurylinklabs.watchtower.enable=true" "$DC"
assert "WATCHTOWER_LABEL_ENABLE set (D-02)" grep -q "WATCHTOWER_LABEL_ENABLE=true" "$DC"
assert "WATCHTOWER_CLEANUP set" grep -q "WATCHTOWER_CLEANUP=true" "$DC"
assert "WATCHTOWER_SCHEDULE uses 6-field cron (D-01)" grep -q "WATCHTOWER_SCHEDULE=0 0 2" "$DC"
assert "Watchtower mounts docker socket" grep -q "docker.sock" "$DC"
assert "Port 443 still exposed for TCP health check (REL-02)" grep -q 'MTG_PORT' "$DC"
assert_not "WATCHTOWER_POLL_INTERVAL not set (conflicts with schedule)" grep -q "WATCHTOWER_POLL_INTERVAL" "$DC"
assert_not "No Docker healthcheck directive (D-04)" grep -q "healthcheck:" "$DC"
assert_not "No Watchtower notifications (D-03)" grep -q "WATCHTOWER_NOTIFICATIONS" "$DC"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
if [[ $FAIL -gt 0 ]]; then
    echo "SMOKE TEST FAILED"
    exit 1
else
    echo "ALL SMOKE TESTS PASSED"
    exit 0
fi
