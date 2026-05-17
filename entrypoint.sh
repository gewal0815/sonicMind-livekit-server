#!/bin/bash
set -euo pipefail

echo "========================================"
echo " SonicMind LiveKit Server - Starting"
echo "========================================"
echo " PORT                         = ${PORT:-NOT_SET}"
echo " LIVEKIT_API_KEY              = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET           = ${LIVEKIT_API_SECRET:+SET}"
echo " REDIS_URL                    = ${REDIS_URL:+SET}"
echo " RAILWAY_TCP_PROXY_DOMAIN     = ${RAILWAY_TCP_PROXY_DOMAIN:-NOT_SET}"
echo " RAILWAY_TCP_PROXY_PORT       = ${RAILWAY_TCP_PROXY_PORT:-NOT_SET}"
echo " RAILWAY_TCP_APPLICATION_PORT = ${RAILWAY_TCP_APPLICATION_PORT:-NOT_SET}"
echo " LIVEKIT_WEBHOOK_URL          = ${LIVEKIT_WEBHOOK_URL:+SET}"
echo " LIVEKIT_WEBHOOK_URLS         = ${LIVEKIT_WEBHOOK_URLS:+SET}"
echo "========================================"

if ! command -v livekit-server >/dev/null 2>&1; then
  echo "FATAL: livekit-server binary not found"
  exit 1
fi

if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set in Railway Variables"
  exit 1
fi

if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set in Railway Variables"
  exit 1
fi

SIGNAL_PORT="${PORT:-8080}"
TCP_PROXY_DOMAIN="${RAILWAY_TCP_PROXY_DOMAIN:-}"
TCP_PROXY_PORT="${RAILWAY_TCP_PROXY_PORT:-}"
TCP_APP_PORT="${RAILWAY_TCP_APPLICATION_PORT:-}"
NODE_IP=""
ICE_TCP_PORT="7881"
USE_EXTERNAL_IP="true"
NODE_IP_MODE="${LIVEKIT_NODE_IP_MODE:-proxy}"

if [ -n "$TCP_PROXY_PORT" ] && [ -n "$TCP_PROXY_DOMAIN" ] && [ -n "$TCP_APP_PORT" ]; then
  echo "TCP proxy detected: ${TCP_PROXY_DOMAIN}:${TCP_PROXY_PORT} -> container:${TCP_APP_PORT}"

  ICE_TCP_PORT="$TCP_PROXY_PORT"

  if [ "$NODE_IP_MODE" = "auto" ]; then
    USE_EXTERNAL_IP="true"
    echo "Node IP mode: auto; LiveKit will discover an external IP via STUN"
  else
    USE_EXTERNAL_IP="false"
    RESOLVED_IP="$(getent ahostsv4 "$TCP_PROXY_DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
    if [ -z "$RESOLVED_IP" ]; then
      RESOLVED_IP="$(getent hosts "$TCP_PROXY_DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || true)"
    fi

    if [ -n "$RESOLVED_IP" ]; then
      NODE_IP="$RESOLVED_IP"
      echo "Resolved TCP proxy domain to node IP: ${NODE_IP}"
    else
      echo "WARNING: Could not resolve ${TCP_PROXY_DOMAIN}; falling back to LiveKit external IP discovery"
      USE_EXTERNAL_IP="true"
    fi
  fi

  if [ "$TCP_APP_PORT" != "$ICE_TCP_PORT" ]; then
    echo "Forwarding Railway TCP application port ${TCP_APP_PORT} to LiveKit ICE TCP port ${ICE_TCP_PORT}"
    if iptables -t nat -A PREROUTING -p tcp --dport "${TCP_APP_PORT}" -j REDIRECT --to-port "${ICE_TCP_PORT}" 2>/dev/null; then
      echo "iptables redirect configured"
    else
      echo "iptables redirect failed; starting haproxy TCP forwarder"
      cat > /tmp/haproxy.cfg <<HACFG
global
  log stdout format raw local0 info

defaults
  mode tcp
  timeout connect 5s
  timeout client 300s
  timeout server 300s
  log global
  option tcplog

listen ice_forwarder
  bind 0.0.0.0:${TCP_APP_PORT}
  server livekit 127.0.0.1:${ICE_TCP_PORT}
HACFG
      haproxy -f /tmp/haproxy.cfg -D
      echo "haproxy TCP forwarder started"
    fi
  else
    echo "Railway TCP application port matches advertised ICE TCP port; no forwarder needed"
  fi
else
  echo "WARNING: Railway TCP proxy variables are missing; using default rtc.tcp_port=${ICE_TCP_PORT}"
  echo "         WebRTC media will fail on Railway unless a TCP proxy is enabled for this service."
fi

REDIS_BLOCK=""
if [ -n "${REDIS_URL:-}" ]; then
  REDIS_PASSWORD="$(echo "$REDIS_URL" | sed -n 's|redis://[^:]*:\([^@]*\)@.*|\1|p')"
  REDIS_HOST_PORT="$(echo "$REDIS_URL" | sed -n 's|redis://[^@]*@\(.*\)|\1|p')"

  if [ -z "$REDIS_HOST_PORT" ]; then
    echo "FATAL: Could not parse REDIS_URL"
    exit 1
  fi

  REDIS_BLOCK="$(cat <<EOF

redis:
  address: ${REDIS_HOST_PORT}
  password: ${REDIS_PASSWORD}
EOF
)"
fi

WEBHOOK_BLOCK=""
WEBHOOK_URLS_RAW="${LIVEKIT_WEBHOOK_URLS:-${LIVEKIT_WEBHOOK_URL:-}}"
if [ -n "$WEBHOOK_URLS_RAW" ]; then
  WEBHOOK_URLS_BLOCK=""
  IFS=',' read -ra WEBHOOK_URL_ITEMS <<< "$WEBHOOK_URLS_RAW"
  for raw_url in "${WEBHOOK_URL_ITEMS[@]}"; do
    url="$(echo "$raw_url" | xargs)"
    if [ -n "$url" ]; then
      WEBHOOK_URLS_BLOCK="${WEBHOOK_URLS_BLOCK}    - ${url}
"
    fi
  done
  if [ -n "$WEBHOOK_URLS_BLOCK" ]; then
    WEBHOOK_BLOCK="$(cat <<EOF

webhook:
  api_key: ${LIVEKIT_API_KEY}
  urls:
${WEBHOOK_URLS_BLOCK}
EOF
)"
  fi
fi

cat > /etc/livekit.yaml <<EOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: info

rtc:
  tcp_port: ${ICE_TCP_PORT}
  port_range_start: 0
  port_range_end: 0
  use_external_ip: ${USE_EXTERNAL_IP}
  force_tcp: false
  use_ice_lite: false
  enable_loopback_candidate: false
${REDIS_BLOCK}

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

room:
  auto_create: true

turn:
  enabled: false
${WEBHOOK_BLOCK}
EOF

echo ""
echo "=== LiveKit runtime summary ==="
echo "Signaling HTTP port: ${SIGNAL_PORT}"
echo "ICE TCP port advertised by LiveKit: ${ICE_TCP_PORT}"
echo "use_external_ip: ${USE_EXTERNAL_IP}"
echo "node_ip: ${NODE_IP:-auto}"
if [ -n "${REDIS_URL:-}" ]; then
  echo "Redis: enabled"
else
  echo "Redis: disabled"
fi
if [ -n "$WEBHOOK_BLOCK" ]; then
  echo "Webhooks: enabled"
else
  echo "Webhooks: disabled"
fi
echo "================================"
echo ""

if [ -n "$NODE_IP" ]; then
  exec livekit-server --config /etc/livekit.yaml --node-ip "$NODE_IP"
else
  exec livekit-server --config /etc/livekit.yaml
fi
