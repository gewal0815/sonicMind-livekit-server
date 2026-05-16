#!/bin/bash
set -uo pipefail

echo "========================================"
echo " SonicMind LiveKit Server — Starting"
echo "========================================"
echo " PORT               = ${PORT:-<not set, defaulting to 8080>}"
echo " LIVEKIT_API_KEY    = ${LIVEKIT_API_KEY:+SET (${#LIVEKIT_API_KEY} chars)}"
echo " LIVEKIT_API_SECRET = ${LIVEKIT_API_SECRET:+SET (${#LIVEKIT_API_SECRET} chars)}"
echo " REDIS_URL          = ${REDIS_URL:+SET}"
echo " RAILWAY_TCP_PROXY  = ${RAILWAY_TCP_PROXY_DOMAIN:-none}:${RAILWAY_TCP_PROXY_PORT:-none}"
echo " TCP_APP_PORT       = ${RAILWAY_TCP_APPLICATION_PORT:-none}"
echo "========================================"
echo " OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 || uname -a)"
echo " Kernel: $(uname -r)"
echo "========================================"

# Verify livekit-server binary
LIVEKIT_BIN="/livekit-server"
if [ ! -x "$LIVEKIT_BIN" ]; then
  LIVEKIT_BIN=$(command -v livekit-server 2>/dev/null || true)
fi
if [ -z "$LIVEKIT_BIN" ] || [ ! -x "$LIVEKIT_BIN" ]; then
  echo "FATAL: livekit-server binary not found"
  exit 1
fi
echo "livekit-server binary: $LIVEKIT_BIN"
echo "livekit-server version: $("$LIVEKIT_BIN" --version 2>&1 || echo 'unknown')"

# --- Required env var checks ---
if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set. Add it to Railway -> livekit-server -> Variables."
  exit 1
fi
if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set. Add it to Railway -> livekit-server -> Variables."
  exit 1
fi

# --- Redis (optional) ---
REDIS_CONFIG=""
if [ -n "${REDIS_URL:-}" ]; then
  REDIS_PASSWORD=$(echo "$REDIS_URL" | sed -n 's|redis://[^:]*:\([^@]*\)@.*|\1|p')
  REDIS_HOST_PORT=$(echo "$REDIS_URL" | sed -n 's|redis://[^@]*@\(.*\)|\1|p')
  if [ -n "$REDIS_HOST_PORT" ]; then
    echo "Redis configured: $REDIS_HOST_PORT"
    REDIS_CONFIG=$(printf 'redis:\n  address: %s\n  password: %s' "$REDIS_HOST_PORT" "$REDIS_PASSWORD")
  fi
else
  echo "REDIS_URL not set - running single-node (no clustering)"
fi

# --- TCP Proxy for ICE ---
TCP_PROXY_DOMAIN="${RAILWAY_TCP_PROXY_DOMAIN:-}"
TCP_PROXY_PORT="${RAILWAY_TCP_PROXY_PORT:-}"
TCP_APP_PORT="${RAILWAY_TCP_APPLICATION_PORT:-}"

ICE_TCP_PORT="7881"
USE_EXTERNAL_IP="false"
NODE_IP=""

if [ -n "$TCP_PROXY_PORT" ] && [ -n "$TCP_PROXY_DOMAIN" ] && [ -n "$TCP_APP_PORT" ]; then
  echo "TCP proxy configured: ${TCP_PROXY_DOMAIN}:${TCP_PROXY_PORT} -> container:${TCP_APP_PORT}"
  ICE_TCP_PORT="$TCP_PROXY_PORT"

  RESOLVED_IP=$(getent ahostsv4 "$TCP_PROXY_DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}' || \
                nslookup "$TCP_PROXY_DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | head -1 || true)
  if [ -n "$RESOLVED_IP" ]; then
    NODE_IP="$RESOLVED_IP"
    echo "Resolved $TCP_PROXY_DOMAIN -> $NODE_IP"
  else
    echo "WARNING: Could not resolve $TCP_PROXY_DOMAIN, using use_external_ip=true"
    USE_EXTERNAL_IP="true"
  fi

  if [ "$TCP_APP_PORT" != "$ICE_TCP_PORT" ]; then
    echo "Setting up port redirect: $TCP_APP_PORT -> $ICE_TCP_PORT"
    if iptables -t nat -A PREROUTING -p tcp --dport "${TCP_APP_PORT}" -j REDIRECT --to-port "${ICE_TCP_PORT}" 2>/dev/null; then
      echo "iptables redirect configured"
    else
      echo "iptables failed, starting haproxy fallback"
      cat > /tmp/haproxy.cfg <<HACFG
global
  log stdout format raw local0 info
defaults
  mode tcp
  timeout connect 5s
  timeout client 300s
  timeout server 300s
listen ice_forwarder
  bind 0.0.0.0:${TCP_APP_PORT}
  server livekit 127.0.0.1:${ICE_TCP_PORT}
HACFG
      haproxy -f /tmp/haproxy.cfg -D && echo "haproxy started"
    fi
  fi
else
  echo "No TCP proxy - ICE will use server auto-detection"
  USE_EXTERNAL_IP="true"
fi

SIGNAL_PORT="${PORT:-8080}"

echo ""
echo "Generating /etc/livekit.yaml ..."

cat > /etc/livekit.yaml <<LKEOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: debug

rtc:
  tcp_port: ${ICE_TCP_PORT}
  use_external_ip: ${USE_EXTERNAL_IP}

${REDIS_CONFIG:+${REDIS_CONFIG}}

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

room:
  auto_create: true

turn:
  enabled: false
LKEOF

echo "=== Generated livekit.yaml ==="
cat /etc/livekit.yaml
echo "=============================="
echo ""
echo "Starting livekit-server on port ${SIGNAL_PORT} ..."

# Run without exec so we capture the exit code for diagnostics
if [ -n "$NODE_IP" ]; then
  "$LIVEKIT_BIN" --config /etc/livekit.yaml --node-ip "$NODE_IP"
else
  "$LIVEKIT_BIN" --config /etc/livekit.yaml
fi
EXIT_CODE=$?

echo ""
echo "!!! livekit-server exited with code $EXIT_CODE !!!"
echo "Sleeping 60s so logs can be read before container restarts..."
sleep 60
exit $EXIT_CODE
