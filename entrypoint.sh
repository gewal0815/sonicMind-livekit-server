#!/bin/sh
set -u

echo "========================================"
echo " SonicMind LiveKit Server — Starting"
echo "========================================"
echo " PORT                   = ${PORT:-NOT_SET}"
echo " LIVEKIT_API_KEY        = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET     = ${LIVEKIT_API_SECRET:+SET}"
echo " REDIS_URL              = ${REDIS_URL:+SET}"
echo " RAILWAY_TCP_APP_PORT   = ${RAILWAY_TCP_APPLICATION_PORT:-NOT_SET}"
echo " RAILWAY_TCP_PROXY_PORT = ${RAILWAY_TCP_PROXY_PORT:-NOT_SET}"
echo "========================================"

# Verify binary
LIVEKIT_BIN="/livekit-server"
if [ ! -x "$LIVEKIT_BIN" ]; then
  echo "FATAL: /livekit-server not found or not executable"
  exit 1
fi

# Required env vars
if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set in Railway Variables"
  exit 1
fi
if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set in Railway Variables"
  exit 1
fi

# HTTP signaling port — always use Railway's $PORT
SIGNAL_PORT="${PORT:-8080}"
echo "HTTP signaling port: $SIGNAL_PORT"

# ICE TCP port — MUST be different from HTTP port.
# Use RAILWAY_TCP_APPLICATION_PORT if it exists and doesn't conflict.
# Otherwise disable ICE TCP (tcp_port: 0) to prevent "address already in use".
ICE_TCP_YAML=""
if [ -n "${RAILWAY_TCP_APPLICATION_PORT:-}" ] && [ "${RAILWAY_TCP_APPLICATION_PORT}" != "$SIGNAL_PORT" ]; then
  ICE_TCP_YAML="  tcp_port: ${RAILWAY_TCP_APPLICATION_PORT}"
  echo "ICE TCP port: ${RAILWAY_TCP_APPLICATION_PORT} (Railway TCP proxy)"
else
  echo "ICE TCP disabled (no TCP proxy or port would conflict with HTTP port)"
fi

# Redis (optional)
REDIS_YAML=""
if [ -n "${REDIS_URL:-}" ]; then
  R_PASS=$(echo "$REDIS_URL" | sed -n 's|redis://[^:]*:\([^@]*\)@.*|\1|p')
  R_HOSTPORT=$(echo "$REDIS_URL" | sed -n 's|redis://[^@]*@\(.*\)|\1|p')
  if [ -n "$R_HOSTPORT" ]; then
    REDIS_YAML=$(printf 'redis:\n  address: %s\n  password: %s' "$R_HOSTPORT" "$R_PASS")
    echo "Redis: $R_HOSTPORT"
  fi
fi

mkdir -p /etc
cat > /etc/livekit.yaml <<EOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: info

rtc:
  use_external_ip: true
${ICE_TCP_YAML}

${REDIS_YAML}

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

room:
  auto_create: true

turn:
  enabled: false
EOF

echo "=== /etc/livekit.yaml ==="
cat /etc/livekit.yaml
echo "========================="
echo ""
echo "Starting livekit-server on port $SIGNAL_PORT ..."
exec "$LIVEKIT_BIN" --config /etc/livekit.yaml
