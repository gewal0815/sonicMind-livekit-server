#!/bin/sh
set -u

echo "========================================"
echo " SonicMind LiveKit Server — Starting"
echo "========================================"
echo " PORT                   = ${PORT:-NOT_SET}"
echo " LIVEKIT_API_KEY        = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET     = ${LIVEKIT_API_SECRET:+SET}"
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


mkdir -p /etc
cat > /etc/livekit.yaml <<EOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: debug

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
